# frozen_string_literal: true

require "net/http"
require_relative "../path"

CASSETTE_PATH = "#{Spec::Path.spec_dir}/support/artifice/vcr_cassettes"
USED_CASSETTES_PATH = "#{Spec::Path.spec_dir}/support/artifice/used_cassettes.txt"
CASSETTE_NAME = ENV.fetch("BUNDLER_SPEC_VCR_CASSETTE_NAME") { "realworld" }

class BundlerVCRHTTP < Net::HTTP
  class RequestHandler
    attr_reader :http, :request, :body, :response_block
    def initialize(http, request, body = nil, &response_block)
      @http = http
      @request = request
      @body = body
      @response_block = response_block
    end

    def handle_request
      handler = self
      request.instance_eval do
        @__vcr_request_handler = handler
      end

      File.open(USED_CASSETTES_PATH, "a+") do |f|
        f.puts request_pair_paths.map {|path| Pathname.new(path).relative_path_from(Spec::Path.source_root).to_s }.join("\n")
      end

      if recorded_response?
        recorded_response
      else
        record_response
      end
    end

    def recorded_response?
      return true if ENV["BUNDLER_SPEC_PRE_RECORDED"]
      request_pair_paths.all? {|f| File.exist?(f) }
    end

    def recorded_response
      File.open(request_pair_paths.last, "rb:ASCII-8BIT") do |response_file|
        response_io = ::Net::BufferedIO.new(response_file)
        ::Net::HTTPResponse.read_new(response_io).tap do |response|
          response.decode_content = request.decode_content if request.respond_to?(:decode_content)
          response.uri = request.uri

          response.reading_body(response_io, request.response_body_permitted?) do
            response_block.call(response) if response_block
          end
        end
      end
    end

    def record_response
      request_path, response_path = *request_pair_paths

      @recording = true

      response = http.request_without_vcr(request, body, &response_block)
      @recording = false
      unless @recording
        require "fileutils"
        FileUtils.mkdir_p(File.dirname(request_path))
        binwrite(request_path, request_to_string(request))
        binwrite(response_path, response_to_string(response))
      end
      response
    end

    def key
      [request["host"] || http.address, request.path, request.method].compact
    end

    def file_name_for_key(key)
      File.join(*key).gsub(/[\:*?"<>|]/, "-")
    end

    def request_pair_paths
      %w[request response].map do |kind|
        File.join(CASSETTE_PATH, CASSETTE_NAME, file_name_for_key(key), kind)
      end
    end

    def request_to_string(request)
      request_string = []
      request_string << "> #{request.method.upcase} #{request.path}"
      request.to_hash.each do |key, value|
        request_string << "> #{key}: #{Array(value).first}"
      end
      request << "" << request.body if request.body
      request_string.join("\n")
    end

    def response_to_string(response)
      headers = response.to_hash
      body = response.body

      response_string = []
      response_string << "HTTP/1.1 #{response.code} #{response.message}"

      headers["content-length"] = [body.bytesize.to_s] if body

      headers.each do |header, value|
        response_string << "#{header}: #{value.join(", ")}"
      end

      response_string << "" << body

      response_string = response_string.join("\n")
      if response_string.respond_to?(:force_encoding)
        response_string.force_encoding("ASCII-8BIT")
      else
        response_string
      end
    end

    def binwrite(path, contents)
      File.open(path, "wb:ASCII-8BIT") {|f| f.write(contents) }
    end
  end

  def start_with_vcr
    if ENV["BUNDLER_SPEC_PRE_RECORDED"]
      raise IOError, "HTTP session already opened" if @started
      @socket = nil
      @started = true
    else
      start_without_vcr
    end
  end

  alias_method :start_without_vcr, :start
  alias_method :start, :start_with_vcr

  def request_with_vcr(request, *args, &block)
    handler = request.instance_eval do
      remove_instance_variable(:@__vcr_request_handler) if defined?(@__vcr_request_handler)
    end || RequestHandler.new(self, request, *args, &block)

    handler.handle_request
  end

  alias_method :request_without_vcr, :request
  alias_method :request, :request_with_vcr
end

require_relative "helpers/artifice"

# Replace Net::HTTP with our VCR subclass
Artifice.replace_net_http(BundlerVCRHTTP)
