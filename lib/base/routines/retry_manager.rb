#--
# Copyright (c) 2013 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

module RightScale
  module CloudApi

    # The routine is responsible for retries/reiterations.
    #
    # If retries are enabled then a singe API call may perform upto DEFAULT_RETRY_COUNT request
    # attempts who may take upto DEFAULT_REITERATION_TIME secsons.
    #
    class RetryManager < Routine
      class Error < CloudApi::HttpError
      end
      
      DEFAULT_RETRY_COUNT      =   2
      DEFAULT_REITERATION_TIME =  10
      DEFAULT_SLEEP_TIME       = 1.0
      
      # Retries manager.
      # 
      # The manager usually takes the very first position in routines chain.
      # It just increments its counters if we did not reach a possible count of retries or
      # complains if there are no attempts left or if API request time is over.
      #
      # There are 2 possible reasons for a retry to be performed:
      #  1. There was a redirect request (HTTP 3xx code)
      #  2. There was an error (HTTP 5xx, 4xx) and
      #
      # Adding strategies [ :full_jitter, :equal_jitter, :decorrelated_jitter]
      #   see http://www.awsarchitectureblog.com/2015/03/backoff.html for details
      def process
        retry_options    = @data[:options][:retry]           || {}
        retry_strategy   = retry_options[:strategy] # nil or garbage is acceptable
        max_retry_count  = retry_options[:count]            || DEFAULT_RETRY_COUNT
        reiteration_time = retry_options[:reiteration_time] || DEFAULT_REITERATION_TIME
        base_sleep_time  = retry_options[:sleep_time]       || DEFAULT_SLEEP_TIME

        # Initialize things on the first run for the current request.
        @data[:vars][:retry] ||= {}
        @data[:vars][:retry][:count] ||= -1        
        @data[:vars][:retry][:count] += 1  # Increment retry attempts count
        @data[:vars][:retry][:orig_body_stream_pos] ||= @data[:request][:body].is_a?(IO) && @data[:request][:body].pos

        attempt = @data[:vars][:retry][:count]        
        # Complain on any issue
        if max_retry_count < attempt
          error_message = "RetryManager: No more retries left."
        elsif Time.now > @data[:vars][:system][:started_at] + reiteration_time
          error_message = "RetryManager: Retry timeout of #{reiteration_time} seconds has been reached."
        end

        # Raise exception if request runs out-of-time or attempts.
        if error_message
          http_data     = @data[:vars][:retry][:http]
          http_code     = http_data && http_data[:code]
          http_message  = http_data && http_data[:message]
          error_message = "#{http_message}\n#{error_message}" if http_message
          raise Error::new(http_code, error_message)
        end

        # Continue (with a delay when needed)
        if attempt > 0 #only sleep on a retry
          previous_sleep = @data[:vars][:retry][:previous_sleep_time] || base_sleep_time
          sleep_time = case retry_strategy
                       when :full_jitter
                         #sleep = random_between(0, base * 2 ** attempt)
                         rand * (base_sleep_time * 2**(attempt-1))
                       when :equal_jitter
                         # sleep = temp / 2 + random_between(0, temp / 2)
                         temp = base_sleep_time * 2 **(attempt-1)
                         temp / 2 + rand * (temp / 2)
                       when :decorrelated_jitter
                         # sleep = random_between(base, previous_sleep * 3)
                         rand * (3*previous_sleep - base_sleep_time) + base_sleep_time
                       else # default behavior, exponential
                         base_sleep_time * 2**(attempt-1)
                       end
          @data[:vars][:retry][:previous_sleep_time] = sleep_time
          cloud_api_logger.log("Sleeping for #{sleep_time} seconds before retry attempt ##{attempt}", :retry_manager)
          sleep(sleep_time)
        end
        
        # Restore file pointer in IO body case.
        if @data[:request][:instance]                          &&
           @data[:request][:instance].is_io?                   &&
           @data[:request][:instance].body.respond_to?('pos')  &&
           @data[:request][:instance].body.respond_to?('pos=') &&
           @data[:request][:instance].body.pos != @data[:vars][:retry][:orig_body_stream_pos]
          cloud_api_logger.log("Restoring file position to #{@data[:vars][:retry][:orig_body_stream_pos]}", :retry_manager)
          @data[:request][:instance].body.pos = @data[:vars][:retry][:orig_body_stream_pos]
        end
        #request params can be removed by another manager, restore them in case this happens, looking at you AWS request signer
        @data[:request][:params] = @data[:request][:orig_params]
      end
    end
    
  end
end
