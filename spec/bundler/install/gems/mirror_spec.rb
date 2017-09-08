# frozen_string_literal: true
require "spec_helper"

RSpec.describe "bundle install with a mirror configured" do
  describe "when the mirror does not match the gem source" do
    before :each do
      gemfile <<-G
        source "file://#{gem_repo1}"

        gem "rack"
      G
      bundle "config --local mirror.http://gems.example.org http://gem-mirror.example.org"
    end

    it "installs from the normal location" do
      bundle :install
      expect(out).to include("Fetching source index from file:#{gem_repo1}")
      expect(the_bundle).to include_gems "rack 1.0"
    end
  end

  describe "when the gem source matches a configured mirror" do
    before :each do
      gemfile <<-G
        # This source is bogus and doesn't have the gem we're looking for
        source "file://#{gem_repo2}"

        gem "rack"
      G
      bundle "config --local mirror.file://#{gem_repo2} file://#{gem_repo1}"
    end

    it "installs the gem from the mirror" do
      bundle :install
      expect(out).to include("Fetching source index from file:#{gem_repo1}")
      expect(out).not_to include("Fetching source index from file:#{gem_repo2}")
      expect(the_bundle).to include_gems "rack 1.0"
    end
  end
end
