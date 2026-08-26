# frozen_string_literal: true

RSpec.describe "the prune setting" do
  describe "with a rubygems source" do
    before do
      gemfile <<-G
        source "https://gem.repo1"

        gem "myrack"
      G

      bundle_config "path vendor/bundle"
    end

    it "keeps the download cache when unset" do
      bundle "install"

      expect(vendored_gems("cache/myrack-1.0.0.gem")).to exist
    end

    it "removes the download cache after installing" do
      bundle_config "prune cache"
      bundle "install"

      expect(vendored_gems("cache")).not_to exist
      expect(vendored_gems("gems/myrack-1.0.0")).to exist
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "removes the download cache after updating" do
      bundle "install"
      bundle "update --all", env: { "BUNDLE_PRUNE" => "cache" }

      expect(vendored_gems("cache")).not_to exist
    end

    it "downloads what the next install is missing" do
      bundle "install", env: { "BUNDLE_PRUNE" => "cache" }
      expect(vendored_gems("cache")).not_to exist

      gemfile <<-G
        source "https://gem.repo1"

        gem "myrack"
        gem "thin"
      G
      bundle "install"

      expect(vendored_gems("cache/thin-1.0.gem")).to exist
      expect(the_bundle).to include_gems "myrack 1.0.0", "thin 1.0"
    end

    it "warns about unknown categories and prunes the known ones" do
      bundle "install", env: { "BUNDLE_PRUNE" => "cache:ext" }

      expect(err).to include("Unknown `prune` category ext")
      expect(vendored_gems("cache")).not_to exist
    end

    it "prunes on bundle clean" do
      bundle "install"
      expect(vendored_gems("cache/myrack-1.0.0.gem")).to exist

      bundle "clean", env: { "BUNDLE_PRUNE" => "cache" }

      expect(vendored_gems("cache")).not_to exist
    end

    it "does not prune on a dry run of bundle clean" do
      bundle "install"

      bundle "clean --dry-run", env: { "BUNDLE_PRUNE" => "cache" }

      expect(vendored_gems("cache/myrack-1.0.0.gem")).to exist
    end
  end

  describe "with a git source" do
    let(:git_path) { lib_path("foo") }
    let(:revision) { revision_for(git_path) }
    let(:checkout) { vendored_gems("bundler/gems/foo-#{revision[0..11]}") }
    let(:mirror) { vendored_gems("cache/bundler/git/foo-#{Digest(:SHA1).hexdigest(git_path.to_s)}") }

    before do
      build_git "foo", path: git_path

      gemfile <<-G
        source "https://gem.repo1"

        gem "foo", :git => "#{git_path}"
      G

      bundle_config "path vendor/bundle"
    end

    it "removes the git metadata but leaves the checkout usable" do
      bundle "install", env: { "BUNDLE_PRUNE" => "git" }

      expect(checkout).to exist
      expect(checkout.join(".git")).not_to exist
      expect(mirror).to exist

      bundle "exec ruby -e 'require \"foo\"; puts FOO'"
      expect(out).to eq("1.0")
    end

    it "removes the git mirror along with the download cache" do
      bundle "install", env: { "BUNDLE_PRUNE" => "cache" }

      expect(mirror).not_to exist
      expect(checkout.join(".git")).to exist
    end

    it "removes both the mirror and the git metadata with the all alias" do
      bundle "install", env: { "BUNDLE_PRUNE" => "all" }

      expect(mirror).not_to exist
      expect(checkout).to exist
      expect(checkout.join(".git")).not_to exist

      bundle "check"
      expect(out).to include("The Gemfile's dependencies are satisfied")
    end
  end
end
