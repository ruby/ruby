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

  describe "#clear_cache" do
    it "invalidates memoized indexes so subsequent reads rebuild them" do
      source = described_class.new

      first_specs = source.specs
      first_installed = source.send(:installed_specs)
      first_default = source.send(:default_specs)
      first_cached = source.send(:cached_specs)

      expect(source.specs).to equal(first_specs)
      expect(source.send(:installed_specs)).to equal(first_installed)
      expect(source.send(:default_specs)).to equal(first_default)
      expect(source.send(:cached_specs)).to equal(first_cached)

      source.clear_cache

      expect(source.specs).not_to equal(first_specs)
      expect(source.send(:installed_specs)).not_to equal(first_installed)
      expect(source.send(:default_specs)).not_to equal(first_default)
      expect(source.send(:cached_specs)).not_to equal(first_cached)
    end

    it "reflects newly-discovered installed gems after clear_cache" do
      source = described_class.new
      foo = Gem::Specification.new("foo", "1.0.0")
      bar = Gem::Specification.new("bar", "1.0.0")

      allow(Bundler.rubygems).to receive(:installed_specs).and_return([foo])
      expect(source.send(:installed_specs).search("bar")).to be_empty

      allow(Bundler.rubygems).to receive(:installed_specs).and_return([foo, bar])
      expect(source.send(:installed_specs).search("bar")).to be_empty

      source.clear_cache

      expect(source.send(:installed_specs).search("bar")).not_to be_empty
    end
  end

  describe "log debug information" do
    it "log the time spent downloading and installing a gem" do
      build_repo2 do
        build_gem "warning"
      end

      gemfile_content = <<~G
        source "https://gem.repo2"
        gem "warning"
      G

      stdout = install_gemfile(gemfile_content, env: { "DEBUG" => "1" })

      expect(stdout).to match(/Downloaded warning in: \d+\.\d+s/)
      expect(stdout).to match(/Installed warning in: \d+\.\d+s/)
    end
  end
end
