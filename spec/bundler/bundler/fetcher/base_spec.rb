# frozen_string_literal: true

RSpec.describe Bundler::Fetcher::Base do
  let(:downloader)  { double(:downloader) }
  let(:remote)      { double(:remote) }
  let(:display_uri) { "http://sample_uri.com" }

  class TestClass < described_class; end

  subject { TestClass.new(downloader, remote, display_uri) }

  describe "#initialize" do
    context "with the abstract Base class" do
      it "should raise an error" do
        expect { described_class.new(downloader, remote, display_uri) }.to raise_error(RuntimeError, "Abstract class")
      end
    end

    context "with a class that inherits the Base class" do
      it "should set the passed attributes" do
        expect(subject.downloader).to eq(downloader)
        expect(subject.remote).to eq(remote)
        expect(subject.display_uri).to eq("http://sample_uri.com")
      end
    end
  end

  describe "#remote_uri" do
    let(:remote_uri_obj) { double(:remote_uri_obj) }

    before { allow(remote).to receive(:uri).and_return(remote_uri_obj) }

    it "should return the remote's uri" do
      expect(subject.remote_uri).to eq(remote_uri_obj)
    end
  end

  describe "#fetch_uri" do
    let(:remote_uri_obj) { Bundler::URI("http://rubygems.org") }

    before { allow(subject).to receive(:remote_uri).and_return(remote_uri_obj) }

    context "when the remote uri's host is rubygems.org" do
      it "should create a copy of the remote uri with index.rubygems.org as the host" do
        fetched_uri = subject.fetch_uri
        expect(fetched_uri.host).to eq("index.rubygems.org")
        expect(fetched_uri).to_not be(remote_uri_obj)
      end
    end

    context "when the remote uri's host is not rubygems.org" do
      let(:remote_uri_obj) { Bundler::URI("http://otherhost.org") }

      it "should return the remote uri" do
        expect(subject.fetch_uri).to eq(Bundler::URI("http://otherhost.org"))
      end
    end

    it "memoizes the fetched uri" do
      expect(remote_uri_obj).to receive(:host).once
      2.times { subject.fetch_uri }
    end
  end

  describe "#available?" do
    it "should return whether the api is available" do
      expect(subject.available?).to be_truthy
    end
  end

  describe "#api_fetcher?" do
    it "should return false" do
      expect(subject.api_fetcher?).to be_falsey
    end
  end
end
