# frozen_string_literal: true

require "bundler/fetcher"
require Spec::Path.rubygems_test_dir.join("local_ssl_server_utilities")

RSpec.describe "Bundler::Fetcher local SSL server", if: Gem::HAVE_OPENSSL do
  include Gem::LocalSSLServerUtilities

  before do
    initialize_ssl_server
  end

  after do
    stop_ssl_server
  end

  describe "#connection" do
    context "non-PQC" do
      it "connects" do
        ssl_server = start_ssl_server
        allow(Bundler.settings).to receive(:[]).and_call_original
        allow(Bundler.settings).to receive(:[]).with(:ssl_ca_cert).and_return(File.join(certs_dir, "ca_cert.pem"))
        response = fetch_path("https://localhost:#{ssl_server.addr[1]}/yaml")
        expect(response.code).to eq("200")
      end

      it "connects with client cert auth" do
        ssl_server = start_ssl_server(
          verify_mode: OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
        )
        allow(Bundler.settings).to receive(:[]).and_call_original
        allow(Bundler.settings).to receive(:[]).with(:ssl_ca_cert).and_return(File.join(certs_dir, "ca_cert.pem"))
        allow(Bundler.settings).to receive(:[]).with(:ssl_client_cert).and_return(File.join(certs_dir, "client.pem"))
        response = fetch_path("https://localhost:#{ssl_server.addr[1]}/yaml")
        expect(response.code).to eq("200")
      end
    end

    context "PQC" do
      before do
        skip_unless_support_pqc
      end

      it "connects" do
        ssl_server = start_ssl_server(mode: :pqc)
        allow(Bundler.settings).to receive(:[]).and_call_original
        allow(Bundler.settings).to receive(:[]).with(:ssl_ca_cert).and_return(File.join(certs_dir, "mldsa65_ca_cert.pem"))
        response = fetch_path("https://localhost:#{ssl_server.addr[1]}/yaml")
        expect(response.code).to eq("200")
      end

      it "connects with client cert auth" do
        ssl_server = start_ssl_server(
          mode: :pqc,
          verify_mode: OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
        )
        allow(Bundler.settings).to receive(:[]).and_call_original
        allow(Bundler.settings).to receive(:[]).with(:ssl_ca_cert).and_return(File.join(certs_dir, "mldsa65_ca_cert.pem"))
        allow(Bundler.settings).to receive(:[]).with(:ssl_client_cert).and_return(File.join(certs_dir, "mldsa65_client.pem"))
        response = fetch_path("https://localhost:#{ssl_server.addr[1]}/yaml")
        expect(response.code).to eq("200")
      end
    end
  end

  def fetch_path(uri)
    uri = Gem::URI(uri)
    remote = double("remote", uri: uri, original_uri: nil)
    fetcher = Bundler::Fetcher.new(remote)

    connection = fetcher.send(:connection)
    connection.request(uri)
  end

  def skip_unless_support_pqc
    without_pqc_support do |message|
      skip message
    end
  end
end
