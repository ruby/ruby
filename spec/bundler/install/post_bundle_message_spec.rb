# frozen_string_literal: true
require "spec_helper"

describe "post bundle message" do
  before :each do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
      gem "activesupport", "2.3.5", :group => [:emo, :test]
      group :test do
        gem "rspec"
      end
      gem "rack-obama", :group => :obama
    G
  end

  let(:bundle_show_message)       { "Use `bundle show [gemname]` to see where a bundled gem is installed." }
  let(:bundle_deployment_message) { "Bundled gems are installed into ./vendor" }
  let(:bundle_complete_message)   { "Bundle complete!" }
  let(:bundle_updated_message)    { "Bundle updated!" }
  let(:installed_gems_stats)      { "4 Gemfile dependencies, 5 gems now installed." }

  describe "for fresh bundle install" do
    it "without any options" do
      bundle :install
      expect(out).to include(bundle_show_message)
      expect(out).not_to include("Gems in the group")
      expect(out).to include(bundle_complete_message)
      expect(out).to include(installed_gems_stats)
    end

    it "with --without one group" do
      bundle "install --without emo"
      expect(out).to include(bundle_show_message)
      expect(out).to include("Gems in the group emo were not installed")
      expect(out).to include(bundle_complete_message)
      expect(out).to include(installed_gems_stats)
    end

    it "with --without two groups" do
      bundle "install --without emo test"
      expect(out).to include(bundle_show_message)
      expect(out).to include("Gems in the groups emo and test were not installed")
      expect(out).to include(bundle_complete_message)
      expect(out).to include("4 Gemfile dependencies, 3 gems now installed.")
    end

    it "with --without more groups" do
      bundle "install --without emo obama test"
      expect(out).to include(bundle_show_message)
      expect(out).to include("Gems in the groups emo, obama and test were not installed")
      expect(out).to include(bundle_complete_message)
      expect(out).to include("4 Gemfile dependencies, 2 gems now installed.")
    end

    describe "with --path and" do
      it "without any options" do
        bundle "install --path vendor"
        expect(out).to include(bundle_deployment_message)
        expect(out).to_not include("Gems in the group")
        expect(out).to include(bundle_complete_message)
      end

      it "with --without one group" do
        bundle "install --without emo --path vendor"
        expect(out).to include(bundle_deployment_message)
        expect(out).to include("Gems in the group emo were not installed")
        expect(out).to include(bundle_complete_message)
      end

      it "with --without two groups" do
        bundle "install --without emo test --path vendor"
        expect(out).to include(bundle_deployment_message)
        expect(out).to include("Gems in the groups emo and test were not installed")
        expect(out).to include(bundle_complete_message)
      end

      it "with --without more groups" do
        bundle "install --without emo obama test --path vendor"
        expect(out).to include(bundle_deployment_message)
        expect(out).to include("Gems in the groups emo, obama and test were not installed")
        expect(out).to include(bundle_complete_message)
      end

      it "with an absolute --path inside the cwd" do
        bundle "install --path #{bundled_app}/cache"
        expect(out).to include("Bundled gems are installed into ./cache")
        expect(out).to_not include("Gems in the group")
        expect(out).to include(bundle_complete_message)
      end

      it "with an absolute --path outside the cwd" do
        bundle "install --path #{bundled_app}_cache"
        expect(out).to include("Bundled gems are installed into #{bundled_app}_cache")
        expect(out).to_not include("Gems in the group")
        expect(out).to include(bundle_complete_message)
      end
    end

    describe "with misspelled or non-existent gem name" do
      it "should report a helpful error message" do
        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "rack"
          gem "not-a-gem", :group => :development
        G
        expect(out).to include("Could not find gem 'not-a-gem' in any of the gem sources listed in your Gemfile.")
      end

      it "should report a helpful error message with reference to cache if available" do
        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "rack"
        G
        bundle :cache
        expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "rack"
          gem "not-a-gem", :group => :development
        G
        expect(out).to include("Could not find gem 'not-a-gem' in any of the gem sources listed in your Gemfile or in gems cached in vendor/cache.")
      end
    end
  end

  describe "for second bundle install run" do
    it "without any options" do
      2.times { bundle :install }
      expect(out).to include(bundle_show_message)
      expect(out).to_not include("Gems in the groups")
      expect(out).to include(bundle_complete_message)
      expect(out).to include(installed_gems_stats)
    end

    it "with --without one group" do
      bundle "install --without emo"
      bundle :install
      expect(out).to include(bundle_show_message)
      expect(out).to include("Gems in the group emo were not installed")
      expect(out).to include(bundle_complete_message)
      expect(out).to include(installed_gems_stats)
    end

    it "with --without two groups" do
      bundle "install --without emo test"
      bundle :install
      expect(out).to include(bundle_show_message)
      expect(out).to include("Gems in the groups emo and test were not installed")
      expect(out).to include(bundle_complete_message)
    end

    it "with --without more groups" do
      bundle "install --without emo obama test"
      bundle :install
      expect(out).to include(bundle_show_message)
      expect(out).to include("Gems in the groups emo, obama and test were not installed")
      expect(out).to include(bundle_complete_message)
    end
  end

  describe "for bundle update" do
    it "without any options" do
      bundle :update
      expect(out).not_to include("Gems in the groups")
      expect(out).to include(bundle_updated_message)
    end

    it "with --without one group" do
      bundle :install, :without => :emo
      bundle :update
      expect(out).to include("Gems in the group emo were not installed")
      expect(out).to include(bundle_updated_message)
    end

    it "with --without two groups" do
      bundle "install --without emo test"
      bundle :update
      expect(out).to include("Gems in the groups emo and test were not installed")
      expect(out).to include(bundle_updated_message)
    end

    it "with --without more groups" do
      bundle "install --without emo obama test"
      bundle :update
      expect(out).to include("Gems in the groups emo, obama and test were not installed")
      expect(out).to include(bundle_updated_message)
    end
  end
end
