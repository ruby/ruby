# frozen_string_literal: true

require_relative "../support/silent_logger"

RSpec.describe "gemcutter's dependency API", :realworld => true do
  context "when Gemcutter API takes too long to respond" do
    before do
      require_rack

      port = find_unused_port
      @server_uri = "http://127.0.0.1:#{port}"

      require_relative "../support/artifice/endpoint_timeout"

      @t = Thread.new do
        server = Rack::Server.start(:app       => EndpointTimeout,
                                    :Host      => "0.0.0.0",
                                    :Port      => port,
                                    :server    => "webrick",
                                    :AccessLog => [],
                                    :Logger    => Spec::SilentLogger.new)
        server.start
      end
      @t.run

      wait_for_server("127.0.0.1", port)
      bundle! "config set timeout 1"
    end

    after do
      Artifice.deactivate
      @t.kill
      @t.join
    end

    it "times out and falls back on the modern index" do
      install_gemfile! <<-G, :artifice => nil
        source "#{@server_uri}"
        gem "rack"
      G

      expect(out).to include("Fetching source index from #{@server_uri}/")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end
  end
end
