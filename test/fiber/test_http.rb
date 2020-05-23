# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'openssl'

require 'test/unit'
require_relative 'scheduler'

class TestFiberHTTP < Test::Unit::TestCase
  def test_get
    Thread.new do
      scheduler = Scheduler.new
      Thread.current.scheduler = scheduler

      Fiber do
        uri = URI("https://www.ruby-lang.org/en/")

        http = Net::HTTP.new uri.host, uri.port
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        body = http.get(uri.path).body

        assert !body.empty?
      end
    end.join
  end
end
