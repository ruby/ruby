# frozen_string_literal: true

RSpec.describe "post bundle message" do
  before :each do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
      gem "activesupport", "2.3.5", :group => [:emo, :test]
      group :test do
        gem "rspec"
      end
      gem "myrack-obama", :group => :obama
    G
  end

  let(:bundle_path)                { "./.bundle" }
  let(:bundle_show_system_message) { "Use `bundle info [gemname]` to see where a bundled gem is installed." }
  let(:bundle_show_path_message)   { "Bundled gems are installed into `#{bundle_path}`" }
  let(:bundle_complete_message)    { "Bundle complete!" }
  let(:bundle_updated_message)     { "Bundle updated!" }
  let(:installed_gems_stats)       { "4 Gemfile dependencies, 5 gems now installed." }
  let(:bundle_show_message)        { Bundler.bundler_major_version < 3 ? bundle_show_system_message : bundle_show_path_message }

  describe "for fresh bundle install" do
    it "shows proper messages according to the configured groups" do
      bundle :install
      expect(out).to include(bundle_show_message)
      expect(out).not_to include("Gems in the group")
      expect(out).to include(bundle_complete_message)
      expect(out).to include(installed_gems_stats)

      bundle "config set --local without emo"
      bundle :install
      expect(out).to include(bundle_show_message)
      expect(out).to include("Gems in the group 'emo' were not installed")
      expect(out).to include(bundle_complete_message)
      expect(out).to include(installed_gems_stats)

      bundle "config set --local without emo test"
      bundle :install
      expect(out).to include(bundle_show_message)
      expect(out).to include("Gems in the groups 'emo' and 'test' were not installed")
      expect(out).to include(bundle_complete_message)
      expect(out).to include("4 Gemfile dependencies, 3 gems now installed.")

      bundle "config set --local without emo obama test"
      bundle :install
      expect(out).to include(bundle_show_message)
      expect(out).to include("Gems in the groups 'emo', 'obama' and 'test' were not installed")
      expect(out).to include(bundle_complete_message)
      expect(out).to include("4 Gemfile dependencies, 2 gems now installed.")
    end

    describe "with `path` configured" do
      let(:bundle_path) { "./vendor" }

      it "shows proper messages according to the configured groups" do
        bundle "config set --local path vendor"
        bundle :install
        expect(out).to include(bundle_show_path_message)
        expect(out).to_not include("Gems in the group")
        expect(out).to include(bundle_complete_message)

        bundle "config set --local path vendor"
        bundle "config set --local without emo"
        bundle :install
        expect(out).to include(bundle_show_path_message)
        expect(out).to include("Gems in the group 'emo' were not installed")
        expect(out).to include(bundle_complete_message)

        bundle "config set --local path vendor"
        bundle "config set --local without emo test"
        bundle :install
        expect(out).to include(bundle_show_path_message)
        expect(out).to include("Gems in the groups 'emo' and 'test' were not installed")
        expect(out).to include(bundle_complete_message)

        bundle "config set --local path vendor"
        bundle "config set --local without emo obama test"
        bundle :install
        expect(out).to include(bundle_show_path_message)
        expect(out).to include("Gems in the groups 'emo', 'obama' and 'test' were not installed")
        expect(out).to include(bundle_complete_message)
      end
    end

    describe "with an absolute `path` inside the cwd configured" do
      let(:bundle_path) { bundled_app("cache") }

      it "shows proper messages according to the configured groups" do
        bundle "config set --local path #{bundle_path}"
        bundle :install
        expect(out).to include("Bundled gems are installed into `./cache`")
        expect(out).to_not include("Gems in the group")
        expect(out).to include(bundle_complete_message)
      end
    end

    describe "with `path` configured to an absolute path outside the cwd" do
      let(:bundle_path) { tmp("not_bundled_app") }

      it "shows proper messages according to the configured groups" do
        bundle "config set --local path #{bundle_path}"
        bundle :install
        expect(out).to include("Bundled gems are installed into `#{tmp("not_bundled_app")}`")
        expect(out).to_not include("Gems in the group")
        expect(out).to include(bundle_complete_message)
      end
    end

    describe "with misspelled or non-existent gem name" do
      before do
        bundle "config set force_ruby_platform true"
      end

      it "should report a helpful error message" do
        install_gemfile <<-G, raise_on_error: false
          source "https://gem.repo1"
          gem "myrack"
          gem "not-a-gem", :group => :development
        G
        expect(err).to include <<-EOS.strip
Could not find gem 'not-a-gem' in rubygems repository https://gem.repo1/ or installed locally.
        EOS
      end

      it "should report a helpful error message with reference to cache if available" do
        install_gemfile <<-G
          source "https://gem.repo1"
          gem "myrack"
        G
        bundle :cache
        expect(bundled_app("vendor/cache/myrack-1.0.0.gem")).to exist
        install_gemfile <<-G, raise_on_error: false
          source "https://gem.repo1"
          gem "myrack"
          gem "not-a-gem", :group => :development
        G
        expect(err).to include("Could not find gem 'not-a-gem' in").
          and include("or in gems cached in vendor/cache.")
      end
    end
  end

  describe "for second bundle install run", bundler: "2" do
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
      expect(out).to include("Gems in the group 'emo' were not installed")
      expect(out).to include(bundle_complete_message)
      expect(out).to include(installed_gems_stats)
    end

    it "with --without two groups" do
      bundle "install --without emo test"
      bundle :install
      expect(out).to include(bundle_show_message)
      expect(out).to include("Gems in the groups 'emo' and 'test' were not installed")
      expect(out).to include(bundle_complete_message)
    end

    it "with --without more groups" do
      bundle "install --without emo obama test"
      bundle :install
      expect(out).to include(bundle_show_message)
      expect(out).to include("Gems in the groups 'emo', 'obama' and 'test' were not installed")
      expect(out).to include(bundle_complete_message)
    end
  end

  describe "for bundle update" do
    it "shows proper messages according to the configured groups" do
      bundle :update, all: true
      expect(out).not_to include("Gems in the groups")
      expect(out).to include(bundle_updated_message)

      bundle "config set --local without emo"
      bundle :install
      bundle :update, all: true
      expect(out).to include("Gems in the group 'emo' were not updated")
      expect(out).to include(bundle_updated_message)

      bundle "config set --local without emo test"
      bundle :install
      bundle :update, all: true
      expect(out).to include("Gems in the groups 'emo' and 'test' were not updated")
      expect(out).to include(bundle_updated_message)

      bundle "config set --local without emo obama test"
      bundle :install
      bundle :update, all: true
      expect(out).to include("Gems in the groups 'emo', 'obama' and 'test' were not updated")
      expect(out).to include(bundle_updated_message)
    end
  end
end
