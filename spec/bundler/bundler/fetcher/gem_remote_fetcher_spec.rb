# frozen_string_literal: true

require "rubygems/remote_fetcher"
require "bundler/fetcher/gem_remote_fetcher"
require_relative "../../support/artifice/helpers/artifice"
require "bundler/vendored_persistent.rb"

RSpec.describe Bundler::Fetcher::GemRemoteFetcher do
  describe "#initialize" do
    context "when ssl_ca_cert setting is not set" do
      before do
        allow(Bundler.settings).to receive(:[]).and_call_original
        allow(Bundler.settings).to receive(:[]).with(:ssl_ca_cert).and_return(nil)
      end

      it "does not append the setting to @cert_files" do
        cert_files = subject.instance_variable_get(:@cert_files)
        gem_cert_files = Gem::Request.get_cert_files
        expect(cert_files).to eq(gem_cert_files)
      end
    end

    context "when ssl_ca_cert setting is set" do
      let(:ca_cert_path) { "/path/to/ca_cert" }

      before do
        allow(Bundler.settings).to receive(:[]).and_call_original
        allow(Bundler.settings).to receive(:[]).with(:ssl_ca_cert).and_return(ca_cert_path)
      end

      it "appends the setting to @cert_files" do
        cert_files = subject.instance_variable_get(:@cert_files)
        gem_cert_files = Gem::Request.get_cert_files
        expect(cert_files).to eq(gem_cert_files + [ca_cert_path])
      end
    end
  end

  describe "Parallel download" do
    it "download using multiple connections from the pool" do
      unless Bundler.rubygems.provides?(">= 4.0.0.dev")
        skip "This example can only run when RubyGems supports multiple http connection pool"
      end

      require_relative "../../support/artifice/helpers/endpoint"
      concurrent_ruby_path = Dir[scoped_base_system_gem_path.join("gems/concurrent-ruby-*/lib/concurrent-ruby")].first
      $LOAD_PATH.unshift(concurrent_ruby_path)
      require "concurrent-ruby"

      require_rack_test
      responses = []

      latch1 = Concurrent::CountDownLatch.new
      latch2 = Concurrent::CountDownLatch.new
      previous_client = Gem::Request::ConnectionPools.client
      dummy_endpoint = Class.new(Endpoint) do
        get "/foo" do
          latch2.count_down
          latch1.wait

          responses << "foo"
        end

        get "/bar" do
          responses << "bar"

          latch1.count_down
        end
      end

      Artifice.activate_with(dummy_endpoint)
      Gem::Request::ConnectionPools.client = Gem::Net::HTTP

      first_request = Thread.new do
        subject.fetch_path("https://example.org/foo")
      end
      second_request = Thread.new do
        latch2.wait
        subject.fetch_path("https://example.org/bar")
      end

      [first_request, second_request].each(&:join)

      expect(responses).to eq(["bar", "foo"])
    ensure
      Artifice.deactivate
      Gem::Request::ConnectionPools.client = previous_client
    end
  end
end
