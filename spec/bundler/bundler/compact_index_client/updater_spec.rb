# frozen_string_literal: true

require "bundler/vendored_net_http"
require "bundler/compact_index_client"
require "bundler/compact_index_client/updater"
require "tmpdir"

RSpec.describe Bundler::CompactIndexClient::Updater do
  subject(:updater) { described_class.new(fetcher) }

  let(:fetcher) { double(:fetcher) }
  let(:local_path) { Pathname.new(Dir.mktmpdir("localpath")).join("versions") }
  let(:etag_path) { Pathname.new(Dir.mktmpdir("localpath-etags")).join("versions.etag") }
  let(:remote_path) { double(:remote_path) }

  let(:full_body) { "abc123" }
  let(:response) { double(:response, body: full_body, is_a?: false) }
  let(:digest) { Digest::SHA256.base64digest(full_body) }

  context "when the local path does not exist" do
    before do
      allow(response).to receive(:[]).with("Repr-Digest") { nil }
      allow(response).to receive(:[]).with("Digest") { nil }
      allow(response).to receive(:[]).with("ETag") { "thisisanetag" }
    end

    it "downloads the file without attempting append" do
      expect(fetcher).to receive(:call).once.with(remote_path, {}) { response }

      updater.update(remote_path, local_path, etag_path)

      expect(local_path.read).to eq(full_body)
      expect(etag_path.read).to eq("thisisanetag")
    end

    it "fails immediately on bad checksum" do
      expect(fetcher).to receive(:call).once.with(remote_path, {}) { response }
      allow(response).to receive(:[]).with("Repr-Digest") { "sha-256=:baddigest:" }

      expect do
        updater.update(remote_path, local_path, etag_path)
      end.to raise_error(Bundler::CompactIndexClient::Updater::MismatchedChecksumError)
    end
  end

  context "when the local path exists" do
    let(:local_body) { "abc" }

    before do
      local_path.open("w") {|f| f.write(local_body) }
    end

    context "with an etag" do
      before do
        etag_path.open("w") {|f| f.write("LocalEtag") }
      end

      let(:headers) do
        {
          "If-None-Match" => "LocalEtag",
          "Range" => "bytes=2-",
        }
      end

      it "does nothing if etags match" do
        expect(fetcher).to receive(:call).once.with(remote_path, headers).and_return(response)
        allow(response).to receive(:is_a?).with(Gem::Net::HTTPPartialContent) { false }
        allow(response).to receive(:is_a?).with(Gem::Net::HTTPNotModified) { true }

        updater.update(remote_path, local_path, etag_path)

        expect(local_path.read).to eq("abc")
        expect(etag_path.read).to eq("LocalEtag")
      end

      it "appends the file if etags do not match" do
        expect(fetcher).to receive(:call).once.with(remote_path, headers).and_return(response)
        allow(response).to receive(:[]).with("Repr-Digest") { "sha-256=:#{digest}:" }
        allow(response).to receive(:[]).with("ETag") { "NewEtag" }
        allow(response).to receive(:is_a?).with(Gem::Net::HTTPPartialContent) { true }
        allow(response).to receive(:is_a?).with(Gem::Net::HTTPNotModified) { false }
        allow(response).to receive(:body) { "c123" }

        updater.update(remote_path, local_path, etag_path)

        expect(local_path.read).to eq(full_body)
        expect(etag_path.read).to eq("NewEtag")
      end

      it "replaces the file if response ignores range" do
        expect(fetcher).to receive(:call).once.with(remote_path, headers).and_return(response)
        allow(response).to receive(:[]).with("Repr-Digest") { "sha-256=:#{digest}:" }
        allow(response).to receive(:[]).with("ETag") { "NewEtag" }
        allow(response).to receive(:body) { full_body }

        updater.update(remote_path, local_path, etag_path)

        expect(local_path.read).to eq(full_body)
        expect(etag_path.read).to eq("NewEtag")
      end

      it "tries the request again if the partial response fails digest check" do
        allow(response).to receive(:[]).with("Repr-Digest") { "sha-256=:baddigest:" }
        allow(response).to receive(:body) { "the beginning of the file changed" }
        allow(response).to receive(:is_a?).with(Gem::Net::HTTPPartialContent) { true }
        expect(fetcher).to receive(:call).once.with(remote_path, headers).and_return(response)

        full_response = double(:full_response, body: full_body, is_a?: false)
        allow(full_response).to receive(:[]).with("Repr-Digest") { "sha-256=:#{digest}:" }
        allow(full_response).to receive(:[]).with("ETag") { "NewEtag" }
        expect(fetcher).to receive(:call).once.with(remote_path, { "If-None-Match" => "LocalEtag" }).and_return(full_response)

        updater.update(remote_path, local_path, etag_path)

        expect(local_path.read).to eq(full_body)
        expect(etag_path.read).to eq("NewEtag")
      end
    end

    context "without an etag file" do
      let(:headers) do
        {
          "Range" => "bytes=2-",
          # This MD5 feature should be deleted after sufficient time has passed since release.
          # From then on, requests that still don't have a saved etag will be made without this header.
          "If-None-Match" => Digest::MD5.hexdigest(local_body),
        }
      end

      it "saves only the etag_path if generated etag matches" do
        expect(fetcher).to receive(:call).once.with(remote_path, headers).and_return(response)
        allow(response).to receive(:is_a?).with(Gem::Net::HTTPPartialContent) { false }
        allow(response).to receive(:is_a?).with(Gem::Net::HTTPNotModified) { true }

        updater.update(remote_path, local_path, etag_path)

        expect(local_path.read).to eq("abc")
        expect(etag_path.read).to eq(headers["If-None-Match"])
      end

      it "appends the file" do
        expect(fetcher).to receive(:call).once.with(remote_path, headers).and_return(response)
        allow(response).to receive(:[]).with("Repr-Digest") { "sha-256=:#{digest}:" }
        allow(response).to receive(:[]).with("ETag") { "OpaqueEtag" }
        allow(response).to receive(:is_a?).with(Gem::Net::HTTPPartialContent) { true }
        allow(response).to receive(:is_a?).with(Gem::Net::HTTPNotModified) { false }
        allow(response).to receive(:body) { "c123" }

        updater.update(remote_path, local_path, etag_path)

        expect(local_path.read).to eq(full_body)
        expect(etag_path.read).to eq("OpaqueEtag")
      end

      it "replaces the file on full file response that ignores range request" do
        expect(fetcher).to receive(:call).once.with(remote_path, headers).and_return(response)
        allow(response).to receive(:[]).with("Repr-Digest") { nil }
        allow(response).to receive(:[]).with("Digest") { nil }
        allow(response).to receive(:[]).with("ETag") { "OpaqueEtag" }
        allow(response).to receive(:is_a?).with(Gem::Net::HTTPPartialContent) { false }
        allow(response).to receive(:is_a?).with(Gem::Net::HTTPNotModified) { false }
        allow(response).to receive(:body) { full_body }

        updater.update(remote_path, local_path, etag_path)

        expect(local_path.read).to eq(full_body)
        expect(etag_path.read).to eq("OpaqueEtag")
      end

      it "tries the request again if the partial response fails digest check" do
        allow(response).to receive(:[]).with("Repr-Digest") { "sha-256=:baddigest:" }
        allow(response).to receive(:body) { "the beginning of the file changed" }
        allow(response).to receive(:is_a?).with(Gem::Net::HTTPPartialContent) { true }
        expect(fetcher).to receive(:call).once.with(remote_path, headers) do
          # During the failed first request, we simulate another process writing the etag.
          # This ensures the second request doesn't generate the md5 etag again but just uses whatever is written.
          etag_path.open("w") {|f| f.write("LocalEtag") }
          response
        end

        full_response = double(:full_response, body: full_body, is_a?: false)
        allow(full_response).to receive(:[]).with("Repr-Digest") { "sha-256=:#{digest}:" }
        allow(full_response).to receive(:[]).with("ETag") { "NewEtag" }
        expect(fetcher).to receive(:call).once.with(remote_path, { "If-None-Match" => "LocalEtag" }).and_return(full_response)

        updater.update(remote_path, local_path, etag_path)

        expect(local_path.read).to eq(full_body)
        expect(etag_path.read).to eq("NewEtag")
      end
    end
  end

  context "when the ETag header is missing" do
    # Regression test for https://github.com/rubygems/bundler/issues/5463
    let(:response) { double(:response, body: full_body) }

    it "treats the response as an update" do
      allow(response).to receive(:[]).with("Repr-Digest") { nil }
      allow(response).to receive(:[]).with("Digest") { nil }
      allow(response).to receive(:[]).with("ETag") { nil }
      expect(fetcher).to receive(:call) { response }

      updater.update(remote_path, local_path, etag_path)
    end
  end

  context "when the download is corrupt" do
    let(:response) { double(:response, body: "") }

    it "raises HTTPError" do
      expect(fetcher).to receive(:call).and_raise(Zlib::GzipFile::Error)

      expect do
        updater.update(remote_path, local_path, etag_path)
      end.to raise_error(Bundler::HTTPError)
    end
  end

  context "when receiving non UTF-8 data and default internal encoding set to ASCII" do
    let(:response) { double(:response, body: "\x8B".b) }

    it "works just fine" do
      old_verbose = $VERBOSE
      previous_internal_encoding = Encoding.default_internal

      begin
        $VERBOSE = false
        Encoding.default_internal = "ASCII"
        allow(response).to receive(:[]).with("Repr-Digest") { nil }
        allow(response).to receive(:[]).with("Digest") { nil }
        allow(response).to receive(:[]).with("ETag") { nil }
        expect(fetcher).to receive(:call) { response }

        updater.update(remote_path, local_path, etag_path)
      ensure
        Encoding.default_internal = previous_internal_encoding
        $VERBOSE = old_verbose
      end
    end
  end
end
