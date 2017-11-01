# frozen_string_literal: true

require "thread"

RSpec.describe "fetching dependencies with a not available mirror", :realworld => true do
  let(:mirror) { @mirror_uri }
  let(:original) { @server_uri }
  let(:server_port) { @server_port }
  let(:host) { "127.0.0.1" }

  before do
    require_rack
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
      global_config("BUNDLE_MIRROR__HTTP://127__0__0__1:#{server_port}/__FALLBACK_TIMEOUT/" => "true",
                    "BUNDLE_MIRROR__HTTP://127__0__0__1:#{server_port}/" => mirror)
    end

    it "install a gem using the original uri when the mirror is not responding" do
      gemfile <<-G
        source "#{original}"
        gem 'weakling'
      G

      bundle :install, :artifice => nil

      expect(out).to include("Installing weakling")
      expect(out).to include("Bundle complete")
      expect(the_bundle).to include_gems "weakling 0.0.3"
    end
  end

  context "with a global fallback timeout" do
    before do
      global_config("BUNDLE_MIRROR__ALL__FALLBACK_TIMEOUT/" => "1",
                    "BUNDLE_MIRROR__ALL" => mirror)
    end

    it "install a gem using the original uri when the mirror is not responding" do
      gemfile <<-G
        source "#{original}"
        gem 'weakling'
      G

      bundle :install, :artifice => nil

      expect(out).to include("Installing weakling")
      expect(out).to include("Bundle complete")
      expect(the_bundle).to include_gems "weakling 0.0.3"
    end
  end

  context "with a specific mirror without a fallback timeout" do
    before do
      global_config("BUNDLE_MIRROR__HTTP://127__0__0__1:#{server_port}/" => mirror)
    end

    it "fails to install the gem with a timeout error" do
      gemfile <<-G
        source "#{original}"
        gem 'weakling'
      G

      bundle :install, :artifice => nil

      expect(out).to include("Fetching source index from #{mirror}")
      expect(out).to include("Retrying fetcher due to error (2/4): Bundler::HTTPError Could not fetch specs from #{mirror}")
      expect(out).to include("Retrying fetcher due to error (3/4): Bundler::HTTPError Could not fetch specs from #{mirror}")
      expect(out).to include("Retrying fetcher due to error (4/4): Bundler::HTTPError Could not fetch specs from #{mirror}")
      expect(out).to include("Could not fetch specs from #{mirror}")
    end

    it "prints each error and warning on a new line" do
      gemfile <<-G
        source "#{original}"
        gem 'weakling'
      G

      bundle :install, :artifice => nil

      expect(last_command.stdout).to include "Fetching source index from #{mirror}/"
      expect(last_command.bundler_err).to include <<-EOS.strip
Retrying fetcher due to error (2/4): Bundler::HTTPError Could not fetch specs from #{mirror}/
Retrying fetcher due to error (3/4): Bundler::HTTPError Could not fetch specs from #{mirror}/
Retrying fetcher due to error (4/4): Bundler::HTTPError Could not fetch specs from #{mirror}/
Could not fetch specs from #{mirror}/
      EOS
    end
  end

  context "with a global mirror without a fallback timeout" do
    before do
      global_config("BUNDLE_MIRROR__ALL" => mirror)
    end

    it "fails to install the gem with a timeout error" do
      gemfile <<-G
        source "#{original}"
        gem 'weakling'
      G

      bundle :install, :artifice => nil

      expect(out).to include("Fetching source index from #{mirror}")
      expect(out).to include("Retrying fetcher due to error (2/4): Bundler::HTTPError Could not fetch specs from #{mirror}")
      expect(out).to include("Retrying fetcher due to error (3/4): Bundler::HTTPError Could not fetch specs from #{mirror}")
      expect(out).to include("Retrying fetcher due to error (4/4): Bundler::HTTPError Could not fetch specs from #{mirror}")
      expect(out).to include("Could not fetch specs from #{mirror}")
    end
  end

  def setup_server
    @server_port = find_unused_port
    @server_uri = "http://#{host}:#{@server_port}"

    require File.expand_path("../../support/artifice/endpoint", __FILE__)

    @server_thread = Thread.new do
      Rack::Server.start(:app       => Endpoint,
                         :Host      => host,
                         :Port      => @server_port,
                         :server    => "webrick",
                         :AccessLog => [],
                         :Logger    => Spec::SilentLogger.new)
    end.run

    wait_for_server(host, @server_port)
  end

  def setup_mirror
    mirror_port = find_unused_port
    @mirror_uri = "http://#{host}:#{mirror_port}"
  end
end
