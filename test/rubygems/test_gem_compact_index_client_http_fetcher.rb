# frozen_string_literal: true

require_relative "helper"
require "rubygems/compact_index_client"

class TestGemCompactIndexClientHTTPFetcher < Gem::TestCase
  class FakeResponse < Gem::Net::HTTPOK
    def initialize(body)
      super("1.1", "200", "OK")
      @fake_body = body
    end

    attr_reader :fake_body
    alias_method :body, :fake_body
  end

  class FakePartialContent < Gem::Net::HTTPPartialContent
    def initialize(body)
      super("1.1", "206", "Partial Content")
      @fake_body = body
    end

    attr_reader :fake_body
    alias_method :body, :fake_body
  end

  class FakeRedirect < Gem::Net::HTTPFound
    def initialize(location)
      super("1.1", "302", "Found")
      self["Location"] = location
    end
  end

  class FakePermanentRedirect < Gem::Net::HTTPPermanentRedirect
    def initialize(location)
      super("1.1", "308", "Permanent Redirect")
      self["Location"] = location
    end
  end

  class FakeNotFound < Gem::Net::HTTPNotFound
    def initialize(error_message = nil)
      super("1.1", "404", "Not Found")
      self["X-Error-Message"] = error_message if error_message
    end
  end

  class FakeNoContent < Gem::Net::HTTPNoContent
    def initialize
      super("1.1", "204", "No Content")
    end
  end

  class FakeRangeNotSatisfiable < Gem::Net::HTTPRangeNotSatisfiable
    def initialize
      super("1.1", "416", "Range Not Satisfiable")
    end
  end

  class FakeRemoteFetcher
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def request(uri, request_class)
      request = request_class.new(uri)
      yield request if block_given?
      @requests << [uri, request]
      response = @responses.fetch(uri.to_s)
      # A mapped exception stands in for a connection that never produced a response.
      raise response if response.is_a?(Exception)
      response
    end
  end

  def fetcher_for(responses)
    remote = FakeRemoteFetcher.new(responses)
    [Gem::CompactIndexClient::HTTPFetcher.new("https://index.example", remote), remote]
  end

  def test_call_joins_path_with_base_uri
    fetcher, remote = fetcher_for("https://index.example/info/a" => FakeResponse.new("data"))

    response = fetcher.call("info/a")

    assert_equal "data", response.body
    assert_equal Gem::URI("https://index.example/info/a"), remote.requests.first.first
  end

  def test_call_returns_not_modified_responses
    response = Gem::Net::HTTPNotModified.new("1.1", "304", "Not Modified")
    fetcher, _remote = fetcher_for("https://index.example/versions" => response)

    assert_same response, fetcher.call("versions")
  end

  def test_call_returns_partial_content_responses
    fetcher, _remote = fetcher_for("https://index.example/versions" => FakePartialContent.new("tail"))

    assert_equal "tail", fetcher.call("versions", "Range" => "bytes=10-").body
  end

  def test_call_applies_request_headers
    fetcher, remote = fetcher_for("https://index.example/versions" => FakeResponse.new("data"))

    fetcher.call("versions", "If-None-Match" => '"abc"', "Range" => "bytes=10-")

    _, request = remote.requests.first
    assert_equal '"abc"', request["If-None-Match"]
    assert_equal "bytes=10-", request["Range"]
  end

  def test_call_follows_redirects
    fetcher, remote = fetcher_for(
      "https://index.example/versions" => FakeRedirect.new("https://mirror.example/versions"),
      "https://mirror.example/versions" => FakeResponse.new("data")
    )

    response = fetcher.call("versions")

    assert_equal "data", response.body
    assert_equal 2, remote.requests.size
  end

  def test_call_follows_permanent_redirects
    fetcher, _remote = fetcher_for(
      "https://index.example/versions" => FakePermanentRedirect.new("https://mirror.example/versions"),
      "https://mirror.example/versions" => FakeResponse.new("data")
    )

    assert_equal "data", fetcher.call("versions").body
  end

  def test_call_resolves_relative_redirect_location
    fetcher, _remote = fetcher_for(
      "https://index.example/versions" => FakeRedirect.new("/v2/versions"),
      "https://index.example/v2/versions" => FakeResponse.new("data")
    )

    assert_equal "data", fetcher.call("versions").body
  end

  def test_call_rejects_https_to_http_redirect
    fetcher, remote = fetcher_for(
      "https://index.example/versions" => FakeRedirect.new("http://mirror.example/versions")
    )

    error = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.call("versions")
    end

    assert_match(%r{redirecting to non-https resource: http://mirror\.example/versions}, error.message)
    assert_equal 1, remote.requests.size
  end

  def test_call_wraps_connection_refused_in_fetch_error
    fetcher, remote = fetcher_for(
      "https://index.example/versions" => Errno::ECONNREFUSED.new("Connection refused")
    )

    error = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.call("versions")
    end

    assert_match(/Errno::ECONNREFUSED/, error.message)
    assert_equal 1, remote.requests.size
  end

  def test_call_wraps_ssl_error_in_fetch_error
    pend "OpenSSL is unavailable" unless Gem::HAVE_OPENSSL

    fetcher, _remote = fetcher_for(
      "https://index.example/versions" => OpenSSL::SSL::SSLError.new("certificate verify failed")
    )

    error = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.call("versions")
    end

    assert_match(/OpenSSL::SSL::SSLError/, error.message)
  end

  def test_call_wraps_socket_error_in_fetch_error
    fetcher, _remote = fetcher_for(
      "https://index.example/versions" => SocketError.new("getaddrinfo: Name or service not known")
    )

    error = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.call("versions")
    end

    assert_match(/SocketError/, error.message)
  end

  def test_call_follows_redirects_from_an_http_source
    remote = FakeRemoteFetcher.new(
      "http://index.example/versions" => FakeRedirect.new("http://mirror.example/versions"),
      "http://mirror.example/versions" => FakeResponse.new("data")
    )
    fetcher = Gem::CompactIndexClient::HTTPFetcher.new("http://index.example", remote)

    assert_equal "data", fetcher.call("versions").body
    assert_equal 2, remote.requests.size
  end

  def test_call_redacts_credentials_in_rejected_redirect
    fetcher, _remote = fetcher_for(
      "https://index.example/versions" => FakeRedirect.new("http://user:s3cr3t@mirror.example/versions")
    )

    error = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.call("versions")
    end

    refute_match(/s3cr3t/, error.message)
    assert_match(%r{redirecting to non-https resource: http://user:REDACTED@mirror\.example/versions}, error.message)
  end

  def test_call_keeps_credentials_on_an_accepted_redirect
    remote = FakeRemoteFetcher.new(
      "https://user:s3cr3t@index.example/versions" => FakeRedirect.new("/v2/versions"),
      "https://user:s3cr3t@index.example/v2/versions" => FakeResponse.new("data")
    )
    fetcher = Gem::CompactIndexClient::HTTPFetcher.new("https://user:s3cr3t@index.example", remote)

    assert_equal "data", fetcher.call("versions").body
    assert_equal "s3cr3t", remote.requests.last.first.password
  end

  def test_call_keeps_credentials_on_an_absolute_same_host_redirect
    remote = FakeRemoteFetcher.new(
      "https://user:s3cr3t@index.example/versions" => FakeRedirect.new("https://index.example/v2/versions"),
      "https://user:s3cr3t@index.example/v2/versions" => FakeResponse.new("data")
    )
    fetcher = Gem::CompactIndexClient::HTTPFetcher.new("https://user:s3cr3t@index.example", remote)

    assert_equal "data", fetcher.call("versions").body
    assert_equal "s3cr3t", remote.requests.last.first.password
  end

  def test_call_drops_credentials_on_a_cross_host_redirect
    remote = FakeRemoteFetcher.new(
      "https://user:s3cr3t@index.example/versions" => FakeRedirect.new("https://mirror.example/versions"),
      "https://mirror.example/versions" => FakeResponse.new("data")
    )
    fetcher = Gem::CompactIndexClient::HTTPFetcher.new("https://user:s3cr3t@index.example", remote)

    assert_equal "data", fetcher.call("versions").body
    assert_nil remote.requests.last.first.userinfo
  end

  def test_call_raises_after_too_many_redirects
    fetcher, _remote = fetcher_for(
      "https://index.example/versions" => FakeRedirect.new("https://index.example/versions")
    )

    error = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.call("versions")
    end

    assert_match(/too many redirects/, error.message)
  end

  def test_call_retries_without_range_and_etag_on_range_not_satisfiable
    requests = []
    remote = Object.new
    remote.define_singleton_method(:request) do |uri, request_class, &block|
      request = request_class.new(uri)
      block&.call(request)
      requests << request
      if request["Range"]
        FakeRangeNotSatisfiable.new
      elsif request["If-None-Match"]
        Gem::Net::HTTPNotModified.new("1.1", "304", "Not Modified")
      else
        FakeResponse.new("full data")
      end
    end

    fetcher = Gem::CompactIndexClient::HTTPFetcher.new("https://index.example", remote)
    response = fetcher.call("versions", "Range" => "bytes=100-", "If-None-Match" => '"abc"')

    assert_equal "full data", response.body
    assert_equal 2, requests.size
    assert_nil requests.last["Range"]
    assert_nil requests.last["If-None-Match"]
  end

  def test_call_raises_on_range_not_satisfiable_without_range
    fetcher, _remote = fetcher_for("https://index.example/versions" => FakeRangeNotSatisfiable.new)

    error = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.call("versions")
    end

    assert_match(/bad response Range Not Satisfiable 416/, error.message)
  end

  def test_call_raises_fetch_error_on_no_content
    fetcher, _remote = fetcher_for("https://index.example/versions" => FakeNoContent.new)

    error = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.call("versions")
    end

    assert_match(/bad response No Content 204/, error.message)
  end

  def test_call_raises_fetch_error_on_failure_response
    fetcher, _remote = fetcher_for("https://index.example/versions" => FakeNotFound.new)

    error = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.call("versions")
    end

    assert_match(/bad response Not Found 404/, error.message)
  end

  def test_call_includes_x_error_message_in_fetch_error
    fetcher, _remote = fetcher_for(
      "https://index.example/versions" => FakeNotFound.new("blocked by corporate proxy policy")
    )

    error = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.call("versions")
    end

    assert_match(/bad response blocked by corporate proxy policy 404/, error.message)
  end
end
