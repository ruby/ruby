# frozen_string_literal: true

require "net/http"
require "bundler/compact_index_client"
require "bundler/compact_index_client/updater"
require "tmpdir"

RSpec.describe Bundler::CompactIndexClient::Updater do
  let(:fetcher) { double(:fetcher) }
  let(:local_path) { Pathname.new Dir.mktmpdir("localpath") }
  let(:remote_path) { double(:remote_path) }

  let!(:updater) { described_class.new(fetcher) }

  context "when the ETag header is missing" do
    # Regression test for https://github.com/rubygems/bundler/issues/5463
    let(:response) { double(:response, :body => "abc123") }

    it "treats the response as an update" do
      expect(response).to receive(:[]).with("ETag") { nil }
      expect(fetcher).to receive(:call) { response }

      updater.update(local_path, remote_path)
    end
  end

  context "when the download is corrupt" do
    let(:response) { double(:response, :body => "") }

    it "raises HTTPError" do
      expect(fetcher).to receive(:call).and_raise(Zlib::GzipFile::Error)

      expect do
        updater.update(local_path, remote_path)
      end.to raise_error(Bundler::HTTPError)
    end
  end

  context "when bundler doesn't have permissions on Dir.tmpdir" do
    it "Errno::EACCES is raised" do
      allow(Bundler::Dir).to receive(:mktmpdir) { raise Errno::EACCES }

      expect do
        updater.update(local_path, remote_path)
      end.to raise_error(Bundler::PermissionError)
    end
  end

  context "when receiving non UTF-8 data and default internal encoding set to ASCII" do
    let(:response) { double(:response, :body => "\x8B".b) }

    it "works just fine" do
      old_verbose = $VERBOSE
      previous_internal_encoding = Encoding.default_internal

      begin
        $VERBOSE = false
        Encoding.default_internal = "ASCII"
        expect(response).to receive(:[]).with("ETag") { nil }
        expect(fetcher).to receive(:call) { response }

        updater.update(local_path, remote_path)
      ensure
        Encoding.default_internal = previous_internal_encoding
        $VERBOSE = old_verbose
      end
    end
  end
end
