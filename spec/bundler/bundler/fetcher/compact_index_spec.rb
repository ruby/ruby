# frozen_string_literal: true

# load CompactIndexClient upfront to prevent thread safety issues during parallel specs
require "bundler/compact_index_client"

RSpec.describe Bundler::Fetcher::CompactIndex do
  let(:downloader)  { double(:downloader) }
  let(:display_uri) { Bundler::URI("http://sampleuri.com") }
  let(:remote)      { double(:remote, cache_slug: "lsjdf", uri: display_uri) }
  let(:gem_remote_fetcher) { nil }
  let(:compact_index) { described_class.new(downloader, remote, display_uri, gem_remote_fetcher) }

  before do
    allow(compact_index).to receive(:log_specs) {}
  end

  describe "#specs_for_names" do
    let(:thread_list) { Thread.list.select {|thread| thread.status == "run" } }
    let(:thread_inspection) { thread_list.map {|th| "  * #{th}:\n    #{th.backtrace_locations.join("\n    ")}" }.join("\n") }

    it "has only one thread open at the end of the run" do
      compact_index.specs_for_names(["lskdjf"])

      thread_count = thread_list.count
      expect(thread_count).to eq(1), "Expected 1 active thread after `#specs_for_names`, but found #{thread_count}. In particular, found:\n#{thread_inspection}"
    end

    it "calls worker#stop during the run" do
      expect_any_instance_of(Bundler::Worker).to receive(:stop).at_least(:once).and_call_original

      compact_index.specs_for_names(["lskdjf"])
    end

    describe "#available?" do
      before do
        allow(compact_index).to receive(:compact_index_client).
          and_return(double(:compact_index_client, update_and_parse_checksums!: true))
      end

      it "returns true" do
        expect(compact_index).to be_available
      end

      context "when OpenSSL is not available" do
        before do
          allow(compact_index).to receive(:require).with("openssl").and_raise(LoadError)
        end

        it "returns true" do
          expect(compact_index).to be_available
        end
      end

      context "when OpenSSL is FIPS-enabled" do
        def remove_cached_md5_availability
          return unless Bundler::SharedHelpers.instance_variable_defined?(:@md5_available)
          Bundler::SharedHelpers.remove_instance_variable(:@md5_available)
        end

        before do
          remove_cached_md5_availability
          stub_const("OpenSSL::OPENSSL_FIPS", true)
        end

        after { remove_cached_md5_availability }

        context "when FIPS-mode is active" do
          before do
            allow(OpenSSL::Digest).to receive(:digest).with("MD5", "").
              and_raise(OpenSSL::Digest::DigestError)
          end

          it "returns false" do
            expect(compact_index).to_not be_available
          end
        end

        it "returns true" do
          expect(compact_index).to be_available
        end
      end
    end

    context "logging" do
      before { allow(compact_index).to receive(:log_specs).and_call_original }

      context "with debug on" do
        before do
          allow(Bundler).to receive_message_chain(:ui, :debug?).and_return(true)
        end

        it "should log at info level" do
          expect(Bundler).to receive_message_chain(:ui, :debug).with('Looking up gems ["lskdjf"]')
          compact_index.specs_for_names(["lskdjf"])
        end
      end

      context "with debug off" do
        before do
          allow(Bundler).to receive_message_chain(:ui, :debug?).and_return(false)
        end

        it "should log at info level" do
          expect(Bundler).to receive_message_chain(:ui, :info).with(".", false)
          compact_index.specs_for_names(["lskdjf"])
        end
      end
    end
  end
end
