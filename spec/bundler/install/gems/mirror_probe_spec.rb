# frozen_string_literal: true

RSpec.describe "fetching dependencies with a not available mirror" do
  before do
    build_repo2

    gemfile <<-G
      source "https://gem.repo2"
      gem 'weakling'
    G
  end

  context "with a specific fallback timeout" do
    before do
      global_config("BUNDLE_MIRROR__HTTPS://GEM__REPO2/__FALLBACK_TIMEOUT/" => "true",
                    "BUNDLE_MIRROR__HTTPS://GEM__REPO2/" => "https://gem.mirror")
    end

    it "install a gem using the original uri when the mirror is not responding" do
      bundle :install, env: { "BUNDLER_SPEC_FAKE_RESOLVE" => "gem.mirror" }, verbose: true

      expect(out).to include("Installing weakling")
      expect(out).to include("Bundle complete")
      expect(the_bundle).to include_gems "weakling 0.0.3"
    end
  end

  context "with a global fallback timeout" do
    before do
      global_config("BUNDLE_MIRROR__ALL__FALLBACK_TIMEOUT/" => "1",
                    "BUNDLE_MIRROR__ALL" => "https://gem.mirror")
    end

    it "install a gem using the original uri when the mirror is not responding" do
      bundle :install, env: { "BUNDLER_SPEC_FAKE_RESOLVE" => "gem.mirror" }

      expect(out).to include("Installing weakling")
      expect(out).to include("Bundle complete")
      expect(the_bundle).to include_gems "weakling 0.0.3"
    end
  end

  context "with a specific mirror without a fallback timeout" do
    before do
      global_config("BUNDLE_MIRROR__HTTPS://GEM__REPO2/" => "https://gem.mirror")
    end

    it "fails to install the gem with a timeout error when the mirror is not responding" do
      bundle :install, artifice: "compact_index_mirror_down", raise_on_error: false

      expect(out).to be_empty
      expect(err).to eq("Could not reach host gem.mirror. Check your network connection and try again.")
    end
  end

  context "with a global mirror without a fallback timeout" do
    before do
      global_config("BUNDLE_MIRROR__ALL" => "https://gem.mirror")
    end

    it "fails to install the gem with a timeout error when the mirror is not responding" do
      bundle :install, artifice: "compact_index_mirror_down", raise_on_error: false

      expect(out).to be_empty
      expect(err).to eq("Could not reach host gem.mirror. Check your network connection and try again.")
    end
  end
end
