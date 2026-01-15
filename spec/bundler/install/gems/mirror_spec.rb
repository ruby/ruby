# frozen_string_literal: true

RSpec.describe "bundle install with a mirror configured" do
  describe "when the mirror does not match the gem source" do
    before :each do
      gemfile <<-G
        source "https://gem.repo1"

        gem "myrack"
      G
      bundle "config set --local mirror.http://gems.example.org http://gem-mirror.example.org"
    end

    it "installs from the normal location" do
      bundle :install
      expect(out).to include("Fetching gem metadata from https://gem.repo1")
      expect(the_bundle).to include_gems "myrack 1.0"
    end
  end

  describe "when the gem source matches a configured mirror" do
    before :each do
      gemfile <<-G
        # This source is bogus and doesn't have the gem we're looking for
        source "https://gem.repo2"

        gem "myrack"
      G
      bundle "config set --local mirror.https://gem.repo2 https://gem.repo1"
    end

    it "installs the gem from the mirror" do
      bundle :install, artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo1.to_s }
      expect(out).to include("Fetching gem metadata from https://gem.repo1")
      expect(out).not_to include("Fetching gem metadata from https://gem.repo2")
      expect(the_bundle).to include_gems "myrack 1.0"
    end
  end
end
