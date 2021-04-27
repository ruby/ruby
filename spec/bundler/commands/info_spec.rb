# frozen_string_literal: true

RSpec.describe "bundle info" do
  context "with a standard Gemfile" do
    before do
      build_repo2 do
        build_gem "has_metadata" do |s|
          s.metadata = {
            "bug_tracker_uri"   => "https://example.com/user/bestgemever/issues",
            "changelog_uri"     => "https://example.com/user/bestgemever/CHANGELOG.md",
            "documentation_uri" => "https://www.example.info/gems/bestgemever/0.0.1",
            "homepage_uri"      => "https://bestgemever.example.io",
            "mailing_list_uri"  => "https://groups.example.com/bestgemever",
            "source_code_uri"   => "https://example.com/user/bestgemever",
            "wiki_uri"          => "https://example.com/user/bestgemever/wiki",
          }
        end
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rails"
        gem "has_metadata"
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

    it "complains if gem not in bundle" do
      bundle "info missing", :raise_on_error => false
      expect(err).to eq("Could not find gem 'missing'.")
    end

    it "warns if path no longer exists on disk" do
      FileUtils.rm_rf(default_bundle_path("gems", "rails-2.3.2"))

      bundle "info rails --path"

      expect(err).to match(/has been deleted/i)
      expect(err).to match(default_bundle_path("gems", "rails-2.3.2").to_s)
    end

    context "given a default gem shippped in ruby", :ruby_repo do
      it "prints information about the default gem" do
        bundle "info rdoc"
        expect(out).to include("* rdoc")
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
  end

  context "with a git repo in the Gemfile" do
    before :each do
      @git = build_git "foo", "1.0"
    end

    it "prints out git info" do
      install_gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G
      expect(the_bundle).to include_gems "foo 1.0"

      bundle "info foo"
      expect(out).to include("foo (1.0 #{@git.ref_for("master", 6)}")
    end

    it "prints out branch names other than master" do
      update_git "foo", :branch => "omg" do |s|
        s.write "lib/foo.rb", "FOO = '1.0.omg'"
      end
      @revision = revision_for(lib_path("foo-1.0"))[0...6]

      install_gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}", :branch => "omg"
      G
      expect(the_bundle).to include_gems "foo 1.0.omg"

      bundle "info foo"
      expect(out).to include("foo (1.0 #{@git.ref_for("omg", 6)}")
    end

    it "doesn't print the branch when tied to a ref" do
      sha = revision_for(lib_path("foo-1.0"))
      install_gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}", :ref => "#{sha}"
      G

      bundle "info foo"
      expect(out).to include("foo (1.0 #{sha[0..6]})")
    end

    it "handles when a version is a '-' prerelease" do
      @git = build_git("foo", "1.0.0-beta.1", :path => lib_path("foo"))
      install_gemfile <<-G
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
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
        gem "rack-obama"
      G

      bundle "info rac"
      expect(out).to match(/\A1 : rack\n2 : rack-obama\n0 : - exit -(\n>)?\z/)
    end
  end

  context "with an invalid regexp for gem name" do
    it "does not find the gem" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails"
      G

      invalid_regexp = "[]"

      bundle "info #{invalid_regexp}", :raise_on_error => false
      expect(err).to include("Could not find gem '#{invalid_regexp}'.")
    end
  end

  context "with without configured" do
    it "does not find the gem, but gives a helpful error" do
      bundle "config without test"

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails", group: :test
      G

      bundle "info rails", :raise_on_error => false
      expect(err).to include("Could not find gem 'rails', because it's in the group 'test', configured to be ignored.")
    end
  end
end
