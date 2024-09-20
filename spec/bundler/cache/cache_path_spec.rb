# frozen_string_literal: true

RSpec.describe "bundle package" do
  before do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G
  end

  context "with --cache-path" do
    it "caches gems at given path" do
      bundle :cache, "cache-path" => "vendor/cache-foo"
      expect(bundled_app("vendor/cache-foo/myrack-1.0.0.gem")).to exist
    end
  end

  context "with config cache_path" do
    it "caches gems at given path" do
      bundle "config set cache_path vendor/cache-foo"
      bundle :cache
      expect(bundled_app("vendor/cache-foo/myrack-1.0.0.gem")).to exist
    end
  end

  context "with absolute --cache-path" do
    it "caches gems at given path" do
      bundle :cache, "cache-path" => bundled_app("vendor/cache-foo")
      expect(bundled_app("vendor/cache-foo/myrack-1.0.0.gem")).to exist
    end
  end
end
