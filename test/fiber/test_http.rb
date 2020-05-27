# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'openssl'

require 'test/unit'
require_relative 'scheduler'

require 'webrick'

class TestFiberHTTP < Test::Unit::TestCase
  def test_get
    server = nil

    server_thread = Thread.new do
      server = WEBrick::HTTPServer.new Port: 8000

      server.mount_proc '/' do |req, res|
        res.body = 'Hello, world!'
      end

      server.start
    end

    Thread.new do
      scheduler = Scheduler.new
      Thread.current.scheduler = scheduler

      Fiber do
        uri = URI("http://localhost:8000/")

        http = Net::HTTP.new(uri.host, uri.port)
        body = http.get(uri.path).body

        assert body, 'Hello, world!'
      end
    end.join

    server.shutdown
    server_thread.join
  end
end
