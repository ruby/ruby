# frozen_string_literal: true

RSpec.describe "bundle install with git sources and sparse_checkout" do
  describe "with sparse_checkout option" do
    it "only checks out the specified directory" do
      build_lib "foo", "1.0", path: lib_path("monorepo/packages/foo")
      build_lib "bar", "2.0", path: lib_path("monorepo/packages/bar")
      build_git "monorepo", path: lib_path("monorepo"), gemspec: false

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", git: "#{lib_path("monorepo")}",
                   sparse_checkout: "packages/foo",
                   glob: "packages/foo/*.gemspec"
      G

      expect(the_bundle).to include_gems "foo 1.0"

      # Verify only sparse_checkout dir exists (when git 2.25+)
      gem_path = Dir[default_bundle_path("bundler/gems/monorepo-*")].first
      git_version = Gem::Version.new(`git --version`.match(/\d+\.\d+\.\d+/)[0])
      if git_version >= Gem::Version.new("2.25.0")
        expect(Dir.exist?("#{gem_path}/packages/foo")).to be true
        expect(Dir.exist?("#{gem_path}/packages/bar")).to be false
      end
    end
  end

  describe "lockfile round-trip" do
    it "preserves sparse_checkout in lockfile" do
      build_lib "foo", "1.0", path: lib_path("monorepo/packages/foo")
      build_git "monorepo", path: lib_path("monorepo"), gemspec: false

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", git: "#{lib_path("monorepo")}",
                   sparse_checkout: "packages/foo",
                   glob: "packages/foo/*.gemspec"
      G

      lockfile_content = File.read(bundled_app_lock)
      expect(lockfile_content).to include("sparse_checkout: packages/foo")

      # Re-run bundle install with existing lockfile
      bundle :install
      expect(the_bundle).to include_gems "foo 1.0"
    end
  end

  describe "multiple gems from same repo with different sparse_checkouts" do
    it "creates separate sources for each sparse_checkout" do
      build_lib "foo", "1.0", path: lib_path("monorepo/packages/foo")
      build_lib "bar", "2.0", path: lib_path("monorepo/packages/bar")
      build_git "monorepo", path: lib_path("monorepo"), gemspec: false

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", git: "#{lib_path("monorepo")}",
                   sparse_checkout: "packages/foo",
                   glob: "packages/foo/*.gemspec"
        gem "bar", git: "#{lib_path("monorepo")}",
                   sparse_checkout: "packages/bar",
                   glob: "packages/bar/*.gemspec"
      G

      expect(the_bundle).to include_gems "foo 1.0", "bar 2.0"

      # Different sparse_checkouts = different cache directories
      cache_dirs = Dir[default_bundle_path("cache/bundler/git/monorepo-*")]
      expect(cache_dirs.size).to eq(2)
    end
  end
end
