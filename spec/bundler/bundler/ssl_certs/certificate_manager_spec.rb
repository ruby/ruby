# frozen_string_literal: true

require "bundler/ssl_certs/certificate_manager"

RSpec.describe Bundler::SSLCerts::CertificateManager do
  let(:rubygems_path)      { root }
  let(:stub_cert)          { File.join(root.to_s, "lib", "rubygems", "ssl_certs", "rubygems.org", "ssl-cert.pem") }
  let(:rubygems_certs_dir) { File.join(root.to_s, "lib", "rubygems", "ssl_certs", "rubygems.org") }

  subject { described_class.new(rubygems_path) }

  # Pretend bundler root is rubygems root
  before do
    # Backing up rubygems ceriticates
    FileUtils.mv(rubygems_certs_dir, rubygems_certs_dir + ".back") if ruby_core?

    FileUtils.mkdir_p(rubygems_certs_dir)
    FileUtils.touch(stub_cert)
  end

  after do
    FileUtils.rm_rf(rubygems_certs_dir)

    # Restore rubygems certificates
    FileUtils.mv(rubygems_certs_dir + ".back", rubygems_certs_dir) if ruby_core?
  end

  describe "#update_from" do
    let(:cert_manager) { double(:cert_manager) }

    before { allow(described_class).to receive(:new).with(rubygems_path).and_return(cert_manager) }

    it "should update the certs through a new certificate manager" do
      allow(cert_manager).to receive(:update!)
      expect(described_class.update_from!(rubygems_path)).to be_nil
    end
  end

  describe "#initialize" do
    it "should set bundler_cert_path as path of the subdir with bundler ssl certs" do
      expect(subject.bundler_cert_path).to eq(File.join(root, "lib/bundler/ssl_certs"))
    end

    it "should set bundler_certs as the paths of the bundler ssl certs" do
      expect(subject.bundler_certs).to include(File.join(root, "lib/bundler/ssl_certs/rubygems.global.ssl.fastly.net/DigiCertHighAssuranceEVRootCA.pem"))
      expect(subject.bundler_certs).to include(File.join(root, "lib/bundler/ssl_certs/index.rubygems.org/GlobalSignRootCA.pem"))
    end

    context "when rubygems_path is not nil" do
      it "should set rubygems_certs" do
        expect(subject.rubygems_certs).to include(File.join(root, "lib", "rubygems", "ssl_certs", "rubygems.org", "ssl-cert.pem"))
      end
    end
  end

  describe "#up_to_date?" do
    context "when bundler certs and rubygems certs are the same" do
      before do
        bundler_certs = Dir[File.join(root.to_s, "lib", "bundler", "ssl_certs", "**", "*.pem")]
        FileUtils.rm(stub_cert)
        FileUtils.cp(bundler_certs, rubygems_certs_dir)
      end

      it "should return true" do
        expect(subject).to be_up_to_date
      end
    end

    context "when bundler certs and rubygems certs are not the same" do
      it "should return false" do
        expect(subject).to_not be_up_to_date
      end
    end
  end

  describe "#update!" do
    context "when certificate manager is not up to date" do
      before do
        allow(subject).to receive(:up_to_date?).and_return(false)
        allow(bundler_fileutils).to receive(:rm)
        allow(bundler_fileutils).to receive(:cp)
      end

      it "should remove the current bundler certs" do
        expect(bundler_fileutils).to receive(:rm).with(subject.bundler_certs)
        subject.update!
      end

      it "should copy the rubygems certs into bundler certs" do
        expect(bundler_fileutils).to receive(:cp).with(subject.rubygems_certs, subject.bundler_cert_path)
        subject.update!
      end

      it "should return nil" do
        expect(subject.update!).to be_nil
      end
    end

    context "when certificate manager is up to date" do
      before { allow(subject).to receive(:up_to_date?).and_return(true) }

      it "should return nil" do
        expect(subject.update!).to be_nil
      end
    end
  end

  describe "#connect_to" do
    let(:host)                 { "http://www.host.com" }
    let(:http)                 { Net::HTTP.new(host, 443) }
    let(:cert_store)           { OpenSSL::X509::Store.new }
    let(:http_header_response) { double(:http_header_response) }

    before do
      allow(Net::HTTP).to receive(:new).with(host, 443).and_return(http)
      allow(OpenSSL::X509::Store).to receive(:new).and_return(cert_store)
      allow(http).to receive(:head).with("/").and_return(http_header_response)
    end

    it "should use ssl for the http request" do
      expect(http).to receive(:use_ssl=).with(true)
      subject.connect_to(host)
    end

    it "use verify peer mode" do
      expect(http).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
      subject.connect_to(host)
    end

    it "set its cert store as a OpenSSL::X509::Store populated with bundler certs" do
      expect(cert_store).to receive(:add_file).at_least(:once)
      expect(http).to receive(:cert_store=).with(cert_store)
      subject.connect_to(host)
    end

    it "return the headers of the request response" do
      expect(subject.connect_to(host)).to eq(http_header_response)
    end
  end
end
