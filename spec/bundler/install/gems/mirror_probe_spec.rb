# frozen_string_literal: true

RSpec.describe "fetching dependencies with a not available mirror" do
  let(:host) { "127.0.0.1" }

  before do
    require_rack_test
    setup_server
    setup_mirror
  end

  after do
    Artifice.deactivate
    @server_thread.kill
    @server_thread.join
  end

  context "with a specific fallback timeout" do
    before do
      global_config("BUNDLE_MIRROR__HTTP://127__0__0__1:#{@server_port}/__FALLBACK_TIMEOUT/" => "true",
                    "BUNDLE_MIRROR__HTTP://127__0__0__1:#{@server_port}/" => @mirror_uri)
    end

    it "install a gem using the original uri when the mirror is not responding" do
      gemfile <<-G
        source "#{@server_uri}"
        gem 'weakling'
      G

      bundle :install, artifice: nil

      expect(out).to include("Installing weakling")
      expect(out).to include("Bundle complete")
      expect(the_bundle).to include_gems "weakling 0.0.3"
    end
  end

  context "with a global fallback timeout" do
    before do
      global_config("BUNDLE_MIRROR__ALL__FALLBACK_TIMEOUT/" => "1",
                    "BUNDLE_MIRROR__ALL" => @mirror_uri)
    end

    it "install a gem using the original uri when the mirror is not responding" do
      gemfile <<-G
        source "#{@server_uri}"
        gem 'weakling'
      G

      bundle :install, artifice: nil

      expect(out).to include("Installing weakling")
      expect(out).to include("Bundle complete")
      expect(the_bundle).to include_gems "weakling 0.0.3"
    end
  end

  context "with a specific mirror without a fallback timeout" do
    before do
      global_config("BUNDLE_MIRROR__HTTP://127__0__0__1:#{@server_port}/" => @mirror_uri)
    end

    it "fails to install the gem with a timeout error when the mirror is not responding" do
      gemfile <<-G
        source "#{@server_uri}"
        gem 'weakling'
      G

      bundle :install, artifice: nil, raise_on_error: false

      expect(out).to include("Fetching source index from #{@mirror_uri}")

      err_lines = err.split("\n")
      expect(err_lines).to include(%r{\ARetrying fetcher due to error \(2/4\): Bundler::HTTPError Could not fetch specs from #{@mirror_uri}/ due to underlying error <})
      expect(err_lines).to include(%r{\ARetrying fetcher due to error \(3/4\): Bundler::HTTPError Could not fetch specs from #{@mirror_uri}/ due to underlying error <})
      expect(err_lines).to include(%r{\ARetrying fetcher due to error \(4/4\): Bundler::HTTPError Could not fetch specs from #{@mirror_uri}/ due to underlying error <})
      expect(err_lines).to include(%r{\ACould not fetch specs from #{@mirror_uri}/ due to underlying error <})
    end
  end

  context "with a global mirror without a fallback timeout" do
    before do
      global_config("BUNDLE_MIRROR__ALL" => @mirror_uri)
    end

    it "fails to install the gem with a timeout error when the mirror is not responding" do
      gemfile <<-G
        source "#{@server_uri}"
        gem 'weakling'
      G

      bundle :install, artifice: nil, raise_on_error: false

      expect(out).to include("Fetching source index from #{@mirror_uri}")

      err_lines = err.split("\n")
      expect(err_lines).to include(%r{\ARetrying fetcher due to error \(2/4\): Bundler::HTTPError Could not fetch specs from #{@mirror_uri}/ due to underlying error <})
      expect(err_lines).to include(%r{\ARetrying fetcher due to error \(3/4\): Bundler::HTTPError Could not fetch specs from #{@mirror_uri}/ due to underlying error <})
      expect(err_lines).to include(%r{\ARetrying fetcher due to error \(4/4\): Bundler::HTTPError Could not fetch specs from #{@mirror_uri}/ due to underlying error <})
      expect(err_lines).to include(%r{\ACould not fetch specs from #{@mirror_uri}/ due to underlying error <})
    end
  end

  def setup_server
    @server_port = find_unused_port
    @server_uri = "http://#{host}:#{@server_port}"

    require_relative "../../support/artifice/compact_index"
    require_relative "../../support/silent_logger"

    require "rackup/server"

    @server_thread = Thread.new do
      Rackup::Server.start(app: CompactIndexAPI,
                           Host: host,
                           Port: @server_port,
                           server: "webrick",
                           AccessLog: [],
                           Logger: Spec::SilentLogger.new)
    end.run

    wait_for_server(host, @server_port)
  end

  def setup_mirror
    @mirror_port = find_unused_port
    @mirror_uri = "http://#{host}:#{@mirror_port}"
  end
end
