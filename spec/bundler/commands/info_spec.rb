# frozen_string_literal: true

RSpec.describe "bundle info" do
  context "with a standard Gemfile" do
    before do
      build_repo2 do
        build_gem "has_metadata" do |s|
          s.metadata = {
            "bug_tracker_uri" => "https://example.com/user/bestgemever/issues",
            "changelog_uri" => "https://example.com/user/bestgemever/CHANGELOG.md",
            "documentation_uri" => "https://www.example.info/gems/bestgemever/0.0.1",
            "homepage_uri" => "https://bestgemever.example.io",
            "mailing_list_uri" => "https://groups.example.com/bestgemever",
            "source_code_uri" => "https://example.com/user/bestgemever",
            "wiki_uri" => "https://example.com/user/bestgemever/wiki",
          }
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "rails"
        gem "has_metadata"
        gem "thin"
      G
    end

    it "creates a Gemfile.lock when invoked with a gem name" do
      FileUtils.rm(bundled_app_lock)

      bundle "info rails"

      expect(bundled_app_lock).to exist
    end

    it "prints information if gem exists in bundle" do
      bundle "info rails"
      expect(out).to include "* rails (2.3.2)
\tSummary: This is just a fake gem for testing
\tHomepage: http://example.com
\tPath: #{default_bundle_path("gems", "rails-2.3.2")}"
    end

    it "prints path if gem exists in bundle" do
      bundle "info rails --path"
      expect(out).to eq(default_bundle_path("gems", "rails-2.3.2").to_s)
    end

    it "prints the path to the running bundler" do
      bundle "info bundler --path"
      expect(out).to eq(root.to_s)
    end

    it "prints gem version if exists in bundle" do
      bundle "info rails --version"
      expect(out).to eq("2.3.2")
    end

    it "doesn't claim that bundler is missing, even if using a custom path without bundler there" do
      bundle "config set --local path vendor/bundle"
      bundle "install"
      bundle "info bundler"
      expect(out).to include("\tPath: #{root}")
      expect(err).not_to match(/The gem bundler is missing/i)
    end

    it "complains if gem not in bundle" do
      bundle "info missing", raise_on_error: false
      expect(err).to eq("Could not find gem 'missing'.")
    end

    it "warns if path does not exist on disk, but specification is there" do
      FileUtils.rm_r(default_bundle_path("gems", "rails-2.3.2"))

      bundle "info rails --path"

      expect(err).to include("The gem rails is missing.")
      expect(err).to include(default_bundle_path("gems", "rails-2.3.2").to_s)

      bundle "info rail --path"
      expect(err).to include("The gem rails is missing.")
      expect(err).to include(default_bundle_path("gems", "rails-2.3.2").to_s)

      bundle "info rails"
      expect(err).to include("The gem rails is missing.")
      expect(err).to include(default_bundle_path("gems", "rails-2.3.2").to_s)
    end

    context "given a default gem shippped in ruby", :ruby_repo do
      it "prints information about the default gem" do
        bundle "info json"
        expect(out).to include("* json")
        expect(out).to include("Default Gem: yes")
      end
    end

    context "given a gem with metadata" do
      it "prints the gem metadata" do
        bundle "info has_metadata"
        expect(out).to include "* has_metadata (1.0)
\tSummary: This is just a fake gem for testing
\tHomepage: http://example.com
\tDocumentation: https://www.example.info/gems/bestgemever/0.0.1
\tSource Code: https://example.com/user/bestgemever
\tWiki: https://example.com/user/bestgemever/wiki
\tChangelog: https://example.com/user/bestgemever/CHANGELOG.md
\tBug Tracker: https://example.com/user/bestgemever/issues
\tMailing List: https://groups.example.com/bestgemever
\tPath: #{default_bundle_path("gems", "has_metadata-1.0")}"
      end
    end

    context "when gem does not have homepage" do
      before do
        build_repo2 do
          build_gem "rails", "2.3.2" do |s|
            s.executables = "rails"
            s.summary = "Just another test gem"
          end
        end
      end

      it "excludes the homepage field from the output" do
        expect(out).to_not include("Homepage:")
      end
    end

    context "when gem has a reverse dependency on any version" do
      it "prints the details" do
        bundle "info myrack"

        expect(out).to include("Reverse Dependencies: \n\t\tthin (1.0) depends on myrack (>= 0)")
      end
    end

    context "when gem has a reverse dependency on a specific version" do
      it "prints the details" do
        bundle "info actionpack"

        expect(out).to include("Reverse Dependencies: \n\t\trails (2.3.2) depends on actionpack (= 2.3.2)")
      end
    end

    context "when gem has no reverse dependencies" do
      it "excludes the reverse dependencies field from the output" do
        bundle "info rails"

        expect(out).not_to include("Reverse Dependencies:")
      end
    end
  end

  context "with a git repo in the Gemfile" do
    before :each do
      @git = build_git "foo", "1.0"
    end

    it "prints out git info" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G
      expect(the_bundle).to include_gems "foo 1.0"

      bundle "info foo"
      expect(out).to include("foo (1.0 #{@git.ref_for("main", 6)}")
    end

    it "prints out branch names other than main" do
      update_git "foo", branch: "omg" do |s|
        s.write "lib/foo.rb", "FOO = '1.0.omg'"
      end
      @revision = revision_for(lib_path("foo-1.0"))[0...6]

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}", :branch => "omg"
      G
      expect(the_bundle).to include_gems "foo 1.0.omg"

      bundle "info foo"
      expect(out).to include("foo (1.0 #{@git.ref_for("omg", 6)}")
    end

    it "doesn't print the branch when tied to a ref" do
      sha = revision_for(lib_path("foo-1.0"))
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}", :ref => "#{sha}"
      G

      bundle "info foo"
      expect(out).to include("foo (1.0 #{sha[0..6]})")
    end

    it "handles when a version is a '-' prerelease" do
      @git = build_git("foo", "1.0.0-beta.1", path: lib_path("foo"))
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", "1.0.0-beta.1", :git => "#{lib_path("foo")}"
      G
      expect(the_bundle).to include_gems "foo 1.0.0.pre.beta.1"

      bundle "info foo"
      expect(out).to include("foo (1.0.0.pre.beta.1")
    end
  end

  context "with a valid regexp for gem name" do
    it "presents alternatives", :readline do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "myrack-obama"
      G

      bundle "info rac"
      expect(out).to match(/\A1 : myrack\n2 : myrack-obama\n0 : - exit -(\n>|\z)/)
    end
  end

  context "with an invalid regexp for gem name" do
    it "does not find the gem" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rails"
      G

      invalid_regexp = "[]"

      bundle "info #{invalid_regexp}", raise_on_error: false
      expect(err).to include("Could not find gem '#{invalid_regexp}'.")
    end
  end

  context "with without configured" do
    it "does not find the gem, but gives a helpful error" do
      bundle "config without test"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rails", group: :test
      G

      bundle "info rails", raise_on_error: false
      expect(err).to include("Could not find gem 'rails', because it's in the group 'test', configured to be ignored.")
    end
  end
end
