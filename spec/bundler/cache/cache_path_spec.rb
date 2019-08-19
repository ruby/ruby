# frozen_string_literal: true

RSpec.describe "bundle package" do
  before do
    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack"
    G
  end

  context "with --cache-path" do
    it "caches gems at given path" do
      bundle :package, "cache-path" => "vendor/cache-foo"
      expect(bundled_app("vendor/cache-foo/rack-1.0.0.gem")).to exist
    end
  end

  context "with config cache_path" do
    it "caches gems at given path" do
      bundle "config set cache_path vendor/cache-foo"
      bundle :package
      expect(bundled_app("vendor/cache-foo/rack-1.0.0.gem")).to exist
    end
  end

  context "with absolute --cache-path" do
    it "caches gems at given path" do
      bundle :package, "cache-path" => "/tmp/cache-foo"
      expect(bundled_app("/tmp/cache-foo/rack-1.0.0.gem")).to exist
    end
  end
end
