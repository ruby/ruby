# frozen_string_literal: true
require "spec_helper"
require "net/http"
require "bundler/compact_index_client"
require "bundler/compact_index_client/updater"

RSpec.describe Bundler::CompactIndexClient::Updater do
  subject(:updater) { described_class.new(fetcher) }

  let(:fetcher) { double(:fetcher) }

  context "when the ETag header is missing" do
    # Regression test for https://github.com/bundler/bundler/issues/5463

    let(:response) { double(:response, :body => "") }
    let(:local_path) { Pathname("/tmp/localpath") }
    let(:remote_path) { double(:remote_path) }

    it "MisMatchedChecksumError is raised" do
      # Twice: #update retries on failure
      expect(response).to receive(:[]).with("Content-Encoding").twice { "" }
      expect(response).to receive(:[]).with("ETag").twice { nil }
      expect(fetcher).to receive(:call).twice { response }

      expect do
        updater.update(local_path, remote_path)
      end.to raise_error(Bundler::CompactIndexClient::Updater::MisMatchedChecksumError)
    end
  end
end
