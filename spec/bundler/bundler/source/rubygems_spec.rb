# frozen_string_literal: true

RSpec.describe Bundler::Source::Rubygems do
  before do
    allow(Bundler).to receive(:root) { Pathname.new("root") }
  end

  describe "caches" do
    it "includes Bundler.app_cache" do
      expect(subject.caches).to include(Bundler.app_cache)
    end

    it "includes GEM_PATH entries" do
      Gem.path.each do |path|
        expect(subject.caches).to include(File.expand_path("#{path}/cache"))
      end
    end

    it "is an array of strings or pathnames" do
      subject.caches.each do |cache|
        expect([String, Pathname]).to include(cache.class)
      end
    end
  end

  describe "#add_remote" do
    context "when the source is an HTTP(s) URI with no host" do
      it "raises error" do
        expect { subject.add_remote("https:rubygems.org") }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#no_remotes?" do
    context "when no remote provided" do
      it "returns a truthy value" do
        expect(described_class.new("remotes" => []).no_remotes?).to be_truthy
      end
    end

    context "when a remote provided" do
      it "returns a falsey value" do
        expect(described_class.new("remotes" => ["https://rubygems.org"]).no_remotes?).to be_falsey
      end
    end
  end
end
