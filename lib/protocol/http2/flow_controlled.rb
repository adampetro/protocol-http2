# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2019-2024, by Samuel Williams.
# Copyright, 2019, by Yuta Iwama.

require_relative "window_update_frame"

module Protocol
	module HTTP2
		module FlowControlled
			def available_size
				@remote_window.available
			end
			
			# This could be negative if the window has been overused due to a change in initial window size.
			def available_frame_size(maximum_frame_size = self.maximum_frame_size)
				available_size = self.available_size
				
				# puts "available_size=#{available_size} maximum_frame_size=#{maximum_frame_size}"
				
				if available_size < maximum_frame_size
					return available_size
				else
					return maximum_frame_size
				end
			end
			
			# Keep track of the amount of data sent, and fail if is too much.
			def consume_remote_window(frame)
				amount = frame.length
				
				# Frames with zero length with the END_STREAM flag set (that is, an empty DATA frame) MAY be sent if there is no available space in either flow-control window.
				if amount.zero? and frame.end_stream?
					# It's okay, we can send. No need to consume, it's empty anyway.
				elsif amount >= 0 and amount <= @remote_window.available
					@remote_window.consume(amount)
				else
					raise FlowControlError, "Trying to send #{frame.length} bytes, exceeded window size: #{@remote_window.available} (#{@remote_window})"
				end
			end
			
			def update_local_window(frame)
				consume_local_window(frame)
				request_window_update
			end
			
			def consume_local_window(frame)
				# For flow-control calculations, the 9-octet frame header is not counted.
				amount = frame.length
				@local_window.consume(amount)
			end
			
			def request_window_update
				if @local_window.limited?
					self.send_window_update(@local_window.wanted)
				end
			end
			
			# Notify the remote end that we are prepared to receive more data:
			def send_window_update(window_increment)
				frame = WindowUpdateFrame.new(self.id)
				frame.pack window_increment
				
				write_frame(frame)
				
				@local_window.expand(window_increment)
			end
			
			def receive_window_update(frame)
				amount = frame.unpack
				
				if amount != 0
					@remote_window.expand(amount)
				else
					raise ProtocolError, "Invalid window size increment: #{amount}!"
				end
			end
			
			# The window has been expanded by the given amount.
			# @parameter size [Integer] the maximum amount of data to send.
			# @return [Boolean] whether the window update was used or not.
			def window_updated(size)
				return false
			end
		end
	end
end
