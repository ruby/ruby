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

  class FakeRedirect < Gem::Net::HTTPFound
    def initialize(location)
      super("1.1", "302", "Found")
      self["Location"] = location
    end
  end

  class FakeNotFound < Gem::Net::HTTPNotFound
    def initialize
      super("1.1", "404", "Not Found")
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
      @responses.fetch(uri.to_s)
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

  def test_call_resolves_relative_redirect_location
    fetcher, _remote = fetcher_for(
      "https://index.example/versions" => FakeRedirect.new("/v2/versions"),
      "https://index.example/v2/versions" => FakeResponse.new("data")
    )

    assert_equal "data", fetcher.call("versions").body
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

  def test_call_raises_fetch_error_on_failure_response
    fetcher, _remote = fetcher_for("https://index.example/versions" => FakeNotFound.new)

    error = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.call("versions")
    end

    assert_match(/bad response Not Found 404/, error.message)
  end
end
