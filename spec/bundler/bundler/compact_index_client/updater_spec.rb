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
      expect(response).to receive(:[]).with("Content-Encoding") { "" }
      expect(response).to receive(:[]).with("ETag") { nil }
      expect(fetcher).to receive(:call) { response }

      updater.update(local_path, remote_path)
    end
  end

  context "when the download is corrupt" do
    let(:response) { double(:response, :body => "") }

    it "raises HTTPError" do
      expect(response).to receive(:[]).with("Content-Encoding") { "gzip" }
      expect(fetcher).to receive(:call) { response }

      expect do
        updater.update(local_path, remote_path)
      end.to raise_error(Bundler::HTTPError)
    end
  end

  context "when bundler doesn't have permissions on Dir.tmpdir" do
    it "Errno::EACCES is raised" do
      local_path # create local path before stubbing mktmpdir
      allow(Bundler::Dir).to receive(:mktmpdir) { raise Errno::EACCES }

      expect do
        updater.update(local_path, remote_path)
      end.to raise_error(Bundler::PermissionError)
    end
  end
end
