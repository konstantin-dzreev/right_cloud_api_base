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

require File.expand_path(File.dirname(__FILE__)) + "/../spec_helper"

describe "" do
  before(:each) do
    logger = Logger.new(STDOUT)
    logger.level = Logger::INFO
    @retrymanager = RightScale::CloudApi::RetryManager.new
    allow(@retrymanager).to receive(:log)
    @request = double(:verb => 'get', :path => 'some/path', :body => 'body', :is_io? => false, :is_error? => false, :is_redirect? => false, :headers => {'header1' => 'val1', 'header2' => 'val2'})
    @test_data = {
      :options     => { :user_agent => 'user_agent_data',
                        :cloud_api_logger => RightScale::CloudApi::CloudApiLogger.new({}),
                        :retry => {
                          :count            => 2,
                          :reiteration_time => 10,
                          :sleep_time       => 0.2
                        },
                      },
      :vars        => { :system => {:block => 'block', :started_at => Time.now}},
      :credentials => {},
      :callbacks   => {},
      :connection  => {:uri => double(:host => 'host.com', :port => '777', :scheme => 'scheme')},
      :request     => {:instance => @request}
    }
    @response   = double(:code => '200', :body => 'body', :to_hash => {:code => '200', :body => 'body'})
    @connection = double(:request => @response)
  end

  context "RightScale::CloudApi::RetryManager" do
    it "works - default exponential" do
      # 1st run
      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 0
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to eq nil

      # 2nd run, +1 count *2 sleep
      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 1
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to eq 0.2

      # 3rd run, +1 count, *2 sleep
      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 2
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to eq 0.4

      #4th run, case 1: default error
      default_rm_error = "RetryManager: No more retries left."
      expect do
        @retrymanager.execute(@test_data)
      end.to raise_error(RightScale::CloudApi::RetryManager::Error, default_rm_error)

      #4th run, case 2: cloud_error + default error
      http_error  = 'Banana.'
      expectation = "#{http_error}\n#{default_rm_error}"
      @test_data[:vars][:retry][:http] = { :code => 777, :message => http_error }
      expect do
        @retrymanager.execute(@test_data)
      end.to raise_error(RightScale::CloudApi::RetryManager::Error, expectation)
    end

    it "works full jitter" do
      @test_data[:options][:retry][:strategy] = :full_jitter
      @test_data[:options][:retry][:count] = 3
      
      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 0
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to eq nil

      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 1
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to be_between(0,0.2)

      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 2
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to be_between(0,0.4)

      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 3
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to be_between(0,0.8)

      #4th run, case 1: default error
      default_rm_error = "RetryManager: No more retries left."
      expect do
        @retrymanager.execute(@test_data)
      end.to raise_error(RightScale::CloudApi::RetryManager::Error, default_rm_error)

      #4th run, case 2: cloud_error + default error
      http_error  = 'Banana.'
      expectation = "#{http_error}\n#{default_rm_error}"
      @test_data[:vars][:retry][:http] = { :code => 777, :message => http_error }
      expect do
        @retrymanager.execute(@test_data)
      end.to raise_error(RightScale::CloudApi::RetryManager::Error, expectation)
    end

    it "works equal jitter" do
      @test_data[:options][:retry][:strategy] = :equal_jitter
      @test_data[:options][:retry][:count] = 3
      
      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 0
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to eq nil

      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 1
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to be_between(0.1,0.2)

      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 2
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to be_between(0.2,0.4)

      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 3
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to be_between(0.4,0.8)

      #4th run, case 1: default error
      default_rm_error = "RetryManager: No more retries left."
      expect do
        @retrymanager.execute(@test_data)
      end.to raise_error(RightScale::CloudApi::RetryManager::Error, default_rm_error)

      #4th run, case 2: cloud_error + default error
      http_error  = 'Banana.'
      expectation = "#{http_error}\n#{default_rm_error}"
      @test_data[:vars][:retry][:http] = { :code => 777, :message => http_error }
      expect do
        @retrymanager.execute(@test_data)
      end.to raise_error(RightScale::CloudApi::RetryManager::Error, expectation)
    end

    it "works decorrelated jitter" do
      @test_data[:options][:retry][:strategy] = :decorrelated_jitter
      @test_data[:options][:retry][:count] = 3
      
      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 0
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to eq nil

      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 1
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to be_between(0.2,0.6)

      previous_sleep_time = @test_data[:vars][:retry][:previous_sleep_time]
      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 2
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to be_between(0.2,3*previous_sleep_time)
      previous_sleep_time = @test_data[:vars][:retry][:previous_sleep_time]

      previous_sleep_time = @test_data[:vars][:retry][:previous_sleep_time]
      @retrymanager.execute(@test_data)
      expect(@test_data[:vars][:retry][:count]).to eq 3
      expect(@test_data[:vars][:retry][:previous_sleep_time]).to be_between(0.2,3*previous_sleep_time)

      #4th run, case 1: default error
      default_rm_error = "RetryManager: No more retries left."
      expect do
        @retrymanager.execute(@test_data)
      end.to raise_error(RightScale::CloudApi::RetryManager::Error, default_rm_error)

      #4th run, case 2: cloud_error + default error
      http_error  = 'Banana.'
      expectation = "#{http_error}\n#{default_rm_error}"
      @test_data[:vars][:retry][:http] = { :code => 777, :message => http_error }
      expect do
        @retrymanager.execute(@test_data)
      end.to raise_error(RightScale::CloudApi::RetryManager::Error, expectation)
    end
  end
end
