# frozen_string_literal: true
require "spec_helper"

describe Bundler::Fetcher::CompactIndex do
  let(:downloader)  { double(:downloader) }
  let(:remote)      { double(:remote, :cache_slug => "lsjdf") }
  let(:display_uri) { URI("http://sampleuri.com") }
  let(:compact_index) { described_class.new(downloader, remote, display_uri) }

  before do
    allow(compact_index).to receive(:log_specs) {}
  end

  describe "#specs_for_names" do
    it "has only one thread open at the end of the run" do
      compact_index.specs_for_names(["lskdjf"])

      thread_count = Thread.list.count {|thread| thread.status == "run" }
      expect(thread_count).to eq 1
    end

    it "calls worker#stop during the run" do
      expect_any_instance_of(Bundler::Worker).to receive(:stop).at_least(:once)

      compact_index.specs_for_names(["lskdjf"])
    end

    describe "#available?" do
      context "when OpenSSL is in FIPS mode", :ruby => ">= 2.0.0" do
        before { stub_const("OpenSSL::OPENSSL_FIPS", true) }

        it "returns false" do
          expect(compact_index).to_not be_available
        end

        it "never requires digest/md5" do
          expect(Kernel).to receive(:require).with("digest/md5").never

          compact_index.available?
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
