# frozen_string_literal: true

RSpec.describe "bundle show", bundler: "2" do
  context "with a standard Gemfile" do
    before :each do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rails"
      G
    end

    it "creates a Gemfile.lock if one did not exist" do
      FileUtils.rm(bundled_app_lock)

      bundle "show"

      expect(bundled_app_lock).to exist
    end

    it "creates a Gemfile.lock when invoked with a gem name" do
      FileUtils.rm(bundled_app_lock)

      bundle "show rails"

      expect(bundled_app_lock).to exist
    end

    it "prints path if gem exists in bundle" do
      bundle "show rails"
      expect(out).to eq(default_bundle_path("gems", "rails-2.3.2").to_s)
    end

    it "prints path if gem exists in bundle (with --paths option)" do
      bundle "show rails --paths"
      expect(out).to eq(default_bundle_path("gems", "rails-2.3.2").to_s)
    end

    it "warns if specification is installed, but path does not exist on disk" do
      FileUtils.rm_r(default_bundle_path("gems", "rails-2.3.2"))

      bundle "show rails"

      expect(err).to match(/is missing/i)
      expect(err).to match(default_bundle_path("gems", "rails-2.3.2").to_s)
    end

    it "prints the path to the running bundler" do
      bundle "show bundler"
      expect(out).to eq(root.to_s)
    end

    it "complains if gem not in bundle" do
      bundle "show missing", raise_on_error: false
      expect(err).to match(/could not find gem 'missing'/i)
    end

    it "prints path of all gems in bundle sorted by name" do
      bundle "show --paths"

      expect(out).to include(default_bundle_path("gems", "rake-#{rake_version}").to_s)
      expect(out).to include(default_bundle_path("gems", "rails-2.3.2").to_s)

      # Gem names are the last component of their path.
      gem_list = out.split.map {|p| p.split("/").last }
      expect(gem_list).to eq(gem_list.sort)
    end

    it "prints summary of gems" do
      bundle "show --verbose"

      expect(out).to include <<~MSG
        * actionmailer (2.3.2)
        \tSummary:  This is just a fake gem for testing
        \tHomepage: http://example.com
        \tStatus:   Up to date
      MSG
    end

    it "includes bundler in the summary of gems" do
      bundle "show --verbose"

      expect(out).to include <<~MSG
        * bundler (#{Bundler::VERSION})
        \tSummary:  The best way to manage your application's dependencies
        \tHomepage: https://bundler.io
        \tStatus:   Up to date
      MSG
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

      bundle :show
      expect(out).to include("foo (1.0 #{@git.ref_for("main", 6)}")
    end

    it "prints out branch names other than main" do
      update_git "foo", branch: "omg" do |s|
        s.write "lib/foo.rb", "FOO = '1.0.omg'"
      end
      @revision = revision_for(lib_path("foo-1.0"))[0...6]

      install_gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}", :branch => "omg"
      G
      expect(the_bundle).to include_gems "foo 1.0.omg"

      bundle :show
      expect(out).to include("foo (1.0 #{@git.ref_for("omg", 6)}")
    end

    it "doesn't print the branch when tied to a ref" do
      sha = revision_for(lib_path("foo-1.0"))
      install_gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}", :ref => "#{sha}"
      G

      bundle :show
      expect(out).to include("foo (1.0 #{sha[0..6]})")
    end

    it "handles when a version is a '-' prerelease" do
      @git = build_git("foo", "1.0.0-beta.1", path: lib_path("foo"))
      install_gemfile <<-G
        gem "foo", "1.0.0-beta.1", :git => "#{lib_path("foo")}"
      G
      expect(the_bundle).to include_gems "foo 1.0.0.pre.beta.1"

      bundle :show
      expect(out).to include("foo (1.0.0.pre.beta.1")
    end
  end

  context "in a fresh gem in a blank git repo" do
    before :each do
      build_git "foo", path: lib_path("foo")
      File.open(lib_path("foo/Gemfile"), "w") {|f| f.puts "gemspec" }
      sys_exec "rm -rf .git && git init", dir: lib_path("foo")
    end

    it "does not output git errors" do
      bundle :show, dir: lib_path("foo")
      expect(err_without_deprecations).to be_empty
    end
  end

  it "performs an automatic bundle install" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "foo"
    G

    bundle "config set auto_install 1"
    bundle :show
    expect(out).to include("Installing foo 1.0")
  end

  context "with a valid regexp for gem name" do
    it "presents alternatives", :readline do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "myrack-obama"
      G

      bundle "show rac"
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

      bundle "show #{invalid_regexp}", raise_on_error: false
      expect(err).to include("Could not find gem '#{invalid_regexp}'.")
    end
  end

  context "--outdated option" do
    # Regression test for https://github.com/rubygems/bundler/issues/5375
    before do
      build_repo2
    end

    it "doesn't update gems to newer versions" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "rails"
      G

      expect(the_bundle).to include_gem("rails 2.3.2")

      update_repo2 do
        build_gem "rails", "3.0.0" do |s|
          s.executables = "rails"
        end
      end

      bundle "show --outdated"

      bundle "install"
      expect(the_bundle).to include_gem("rails 2.3.2")
    end
  end
end

RSpec.describe "bundle show", bundler: "4" do
  pending "shows a friendly error about the command removal"
end
