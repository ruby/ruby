# frozen_string_literal: true

require "bundler/vendored_persistent"

RSpec.describe Bundler::PersistentHTTP do
  describe "#warn_old_tls_version_rubygems_connection" do
    let(:uri) { "https://index.rubygems.org" }
    let(:connection) { instance_double(Bundler::Persistent::Net::HTTP::Persistent::Connection) }
    let(:tls_version) { "TLSv1.2" }
    let(:socket) { double("Socket") }
    let(:socket_io) { double("SocketIO") }

    before do
      allow(connection).to receive_message_chain(:http, :use_ssl?).and_return(!tls_version.nil?)
      allow(socket).to receive(:io).and_return(socket_io) if socket
      connection.instance_variable_set(:@socket, socket)

      if tls_version
        allow(socket_io).to receive(:ssl_version).and_return(tls_version)
      end
    end

    shared_examples_for "does not warn" do
      it "does not warn" do
        allow(Bundler.ui).to receive(:warn).never
        subject.warn_old_tls_version_rubygems_connection(URI(uri), connection)
      end
    end

    shared_examples_for "does warn" do |*expected|
      it "warns" do
        expect(Bundler.ui).to receive(:warn).with(*expected)
        subject.warn_old_tls_version_rubygems_connection(URI(uri), connection)
      end
    end

    context "an HTTPS uri with TLSv1.2" do
      include_examples "does not warn"
    end

    context "without SSL" do
      let(:tls_version) { nil }

      include_examples "does not warn"
    end

    context "without a socket" do
      let(:socket) { nil }

      include_examples "does not warn"
    end

    context "with a different TLD" do
      let(:uri) { "https://foo.bar" }
      include_examples "does not warn"

      context "and an outdated TLS version" do
        let(:tls_version) { "TLSv1" }
        include_examples "does not warn"
      end
    end

    context "with a nonsense TLS version" do
      let(:tls_version) { "BlahBlah2.0Blah" }
      include_examples "does not warn"
    end

    context "with an outdated TLS version" do
      let(:tls_version) { "TLSv1" }
      include_examples "does warn",
        "Warning: Your Ruby version is compiled against a copy of OpenSSL that is very old. " \
        "Starting in January 2018, RubyGems.org will refuse connection requests from these very old versions of OpenSSL. " \
        "If you will need to continue installing gems after January 2018, please follow this guide to upgrade: http://ruby.to/tls-outdated.",
        :wrap => true
    end
  end
end
