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
    it "clears the installed_specs cache" do
      source = described_class.new

      # Access installed_specs to populate the cache
      source.send(:installed_specs)
      expect(source.instance_variable_get(:@installed_specs)).not_to be_nil

      # Expire the cache
      source.clear_cache

      # Cache should be cleared
      expect(source.instance_variable_get(:@installed_specs)).to be_nil
    end

    it "clears the default_specs cache" do
      source = described_class.new

      # Access default_specs to populate the cache
      source.send(:default_specs)
      expect(source.instance_variable_get(:@default_specs)).not_to be_nil

      # Expire the cache
      source.clear_cache

      # Cache should be cleared
      expect(source.instance_variable_get(:@default_specs)).to be_nil
    end

    it "clears the merged specs cache" do
      source = described_class.new

      source.instance_variable_set(:@specs, Bundler::Index.new)
      source.instance_variable_set(:@cached_specs, Bundler::Index.new)

      source.clear_cache

      expect(source.instance_variable_get(:@specs)).to be_nil
      expect(source.instance_variable_get(:@cached_specs)).to be_nil
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
