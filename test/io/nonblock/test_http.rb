# frozen_string_literal: true

require 'net/http'
require 'uri'

require 'test/unit'
require 'socket'
require_relative 'scheduler'

class TestIONonblockHTTP < Test::Unit::TestCase
  def test_get
    Thread.new do
      scheduler = Scheduler.new
      Thread.current.scheduler = scheduler

      Fiber do
        uri = URI("https://www.ruby-lang.org/en/")

        response = Net::HTTP.get(uri)

        assert !response.empty?
      end
    end.join
  end
end
