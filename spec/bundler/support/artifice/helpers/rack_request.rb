# frozen_string_literal: true

require "rack/test"
require "net/http"

module Artifice
  module Net
    # This is an internal object that can receive Rack requests
    # to the application using the Rack::Test API
    class RackRequest
      include Rack::Test::Methods
      attr_reader :app

      def initialize(app)
        @app = app
      end
    end

    class HTTP < ::Net::HTTP
      class << self
        attr_accessor :endpoint
      end

      # Net::HTTP uses a @newimpl instance variable to decide whether
      # to use a legacy implementation. Since we are subclassing
      # Net::HTTP, we must set it
      @newimpl = true

      # We don't need to connect, so blank out this method
      def connect
      end

      # Replace the Net::HTTP request method with a method
      # that converts the request into a Rack request and
      # dispatches it to the Rack endpoint.
      #
      # @param [Net::HTTPRequest] req A Net::HTTPRequest
      #   object, or one if its subclasses
      # @param [optional, String, #read] body This should
      #   be sent as "rack.input". If it's a String, it will
      #   be converted to a StringIO.
      # @return [Net::HTTPResponse]
      #
      # @yield [Net::HTTPResponse] If a block is provided,
      #   this method will yield the Net::HTTPResponse to
      #   it after the body is read.
      def request(req, body = nil, &block)
        rack_request = RackRequest.new(self.class.endpoint)

        req.each_header do |header, value|
          rack_request.header(header, value)
        end

        scheme = use_ssl? ? "https" : "http"
        prefix = "#{scheme}://#{addr_port}"
        body_stream_contents = req.body_stream.read if req.body_stream

        response = rack_request.request("#{prefix}#{req.path}",
          { :method => req.method, :input => body || req.body || body_stream_contents })

        make_net_http_response(response, &block)
      end

      private

      # This method takes a Rack response and creates a Net::HTTPResponse
      # Instead of trying to mock HTTPResponse directly, we just convert
      # the Rack response into a String that looks like a normal HTTP
      # response and call Net::HTTPResponse.read_new
      #
      # @param [Array(#to_i, Hash, #each)] response a Rack response
      # @return [Net::HTTPResponse]
      # @yield [Net::HTTPResponse] If a block is provided, yield the
      #   response to it after the body is read
      def make_net_http_response(response)
        status = response.status
        headers = response.headers
        body = response.body

        response_string = []
        response_string << "HTTP/1.1 #{status} #{Rack::Utils::HTTP_STATUS_CODES[status]}"

        headers.each do |header, value|
          response_string << "#{header}: #{value}"
        end

        response_string << "" << body

        response_io = ::Net::BufferedIO.new(StringIO.new(response_string.join("\n")))
        res = ::Net::HTTPResponse.read_new(response_io)

        res.reading_body(response_io, true) do
          yield res if block_given?
        end

        res
      end
    end
  end
end
