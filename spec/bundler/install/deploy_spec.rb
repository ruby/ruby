# frozen_string_literal: true

RSpec.describe "install in deployment or frozen mode" do
  before do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G
  end

  context "with CLI flags" do
    it "fails without a lockfile and says that --deployment requires a lock" do
      bundle "install --deployment", raise_on_error: false
      expect(err).to include("The --deployment flag requires a lockfile")
    end

    it "fails without a lockfile and says that --frozen requires a lock" do
      bundle "install --frozen", raise_on_error: false
      expect(err).to include("The --frozen flag requires a lockfile")
    end

    it "disallows --deployment --system" do
      bundle "install --deployment --system", raise_on_error: false
      expect(err).to include("You have specified both --deployment")
      expect(err).to include("Please choose only one option")
      expect(exitstatus).to eq(15)
    end

    it "disallows --deployment --path --system" do
      bundle "install --deployment --path . --system", raise_on_error: false
      expect(err).to include("You have specified both --path")
      expect(err).to include("as well as --system")
      expect(err).to include("Please choose only one option")
      expect(exitstatus).to eq(15)
    end

    it "doesn't mess up a subsequent `bundle install` after you try to deploy without a lock" do
      bundle "install --deployment", raise_on_error: false
      bundle :install
      expect(the_bundle).to include_gems "myrack 1.0"
    end

    it "installs gems by default to vendor/bundle" do
      bundle :lock
      bundle "install --deployment"
      expect(out).to include("vendor/bundle")
    end

    it "installs gems to custom path if specified" do
      bundle :lock
      bundle "install --path vendor/bundle2 --deployment"
      expect(out).to include("vendor/bundle2")
    end

    it "works with the --frozen flag" do
      bundle :lock
      bundle "install --frozen"
    end

    it "explodes with the --deployment flag if you make a change and don't check in the lockfile" do
      bundle :lock
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "myrack-obama"
      G

      bundle "install --deployment", raise_on_error: false
      expect(err).to include("frozen mode")
      expect(err).to include("You have added to the Gemfile")
      expect(err).to include("* myrack-obama")
      expect(err).not_to include("You have deleted from the Gemfile")
      expect(err).not_to include("You have changed in the Gemfile")
    end
  end

  it "fails without a lockfile and says that deployment requires a lock" do
    bundle "config deployment true"
    bundle "install", raise_on_error: false
    expect(err).to include("The deployment setting requires a lockfile")
  end

  it "fails without a lockfile and says that frozen requires a lock" do
    bundle "config frozen true"
    bundle "install", raise_on_error: false
    expect(err).to include("The frozen setting requires a lockfile")
  end

  it "still works if you are not in the app directory and specify --gemfile" do
    bundle "install"
    pristine_system_gems :bundler
    bundle "config set --local deployment true"
    bundle "config set --local path vendor/bundle"
    bundle "install --gemfile #{tmp}/bundled_app/Gemfile", dir: tmp
    expect(the_bundle).to include_gems "myrack 1.0"
  end

  it "works if you exclude a group with a git gem" do
    build_git "foo"
    gemfile <<-G
      source "https://gem.repo1"
      group :test do
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      end
    G
    bundle :install
    bundle "config set --local deployment true"
    bundle "config set --local without test"
    bundle :install
  end

  it "works when you bundle exec bundle" do
    skip "doesn't find bundle" if Gem.win_platform?

    bundle :install
    bundle "config set --local deployment true"
    bundle :install
    bundle "exec bundle check", env: { "PATH" => path }
  end

  it "works when using path gems from the same path and the version is specified" do
    build_lib "foo", path: lib_path("nested/foo")
    build_lib "bar", path: lib_path("nested/bar")
    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", "1.0", :path => "#{lib_path("nested")}"
      gem "bar", :path => "#{lib_path("nested")}"
    G

    bundle :install
    bundle "config set --local deployment true"
    bundle :install
  end

  it "works when path gems are specified twice" do
    build_lib "foo", path: lib_path("nested/foo")
    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => "#{lib_path("nested/foo")}"
      gem "foo", :path => "#{lib_path("nested/foo")}"
    G

    bundle :install
    bundle "config set --local deployment true"
    bundle :install
  end

  it "works when there are credentials in the source URL" do
    install_gemfile(<<-G, artifice: "endpoint_strict_basic_authentication", quiet: true)
      source "http://user:pass@localgemserver.test/"

      gem "myrack-obama", ">= 1.0"
    G

    bundle "config set --local deployment true"
    bundle :install, artifice: "endpoint_strict_basic_authentication"
  end

  it "works with sources given by a block" do
    install_gemfile <<-G
      source "https://gem.repo1"
      source "https://gem.repo1" do
        gem "myrack"
      end
    G

    bundle "config set --local deployment true"
    bundle :install

    expect(the_bundle).to include_gems "myrack 1.0"
  end

  context "when replacing a host with the same host with credentials" do
    before do
      bundle "config set --local path vendor/bundle"
      bundle "install"
      gemfile <<-G
        source "http://user_name:password@localgemserver.test/"
        gem "myrack"
      G

      lockfile <<-G
        GEM
          remote: http://localgemserver.test/
          specs:
            myrack (1.0.0)

        PLATFORMS
          #{generic_local_platform}

        DEPENDENCIES
          myrack
      G

      bundle "config set --local deployment true"
    end

    it "allows the replace" do
      bundle :install

      expect(out).to match(/Bundle complete!/)
    end
  end

  describe "with an existing lockfile" do
    before do
      bundle "install"
    end

    it "installs gems by default to vendor/bundle" do
      bundle "config set deployment true"
      expect do
        bundle "install"
      end.not_to change { bundled_app_lock.mtime }
      expect(out).to include("vendor/bundle")
    end

    it "installs gems to custom path if specified" do
      bundle "config set path vendor/bundle2"
      bundle "config set deployment true"
      bundle "install"
      expect(out).to include("vendor/bundle2")
    end

    it "installs gems to custom path if specified, even when configured through ENV" do
      bundle "config set deployment true"
      bundle "install", env: { "BUNDLE_PATH" => "vendor/bundle2" }
      expect(out).to include("vendor/bundle2")
    end

    it "works with the `frozen` setting" do
      bundle "config set frozen true"
      expect do
        bundle "install"
      end.not_to change { bundled_app_lock.mtime }
    end

    it "works with BUNDLE_FROZEN if you didn't change anything" do
      expect do
        bundle :install, env: { "BUNDLE_FROZEN" => "true" }
      end.not_to change { bundled_app_lock.mtime }
    end

    it "explodes with the `deployment` setting if you make a change and don't check in the lockfile" do
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "myrack-obama"
      G

      bundle "config set --local deployment true"
      bundle :install, raise_on_error: false
      expect(err).to include("frozen mode")
      expect(err).to include("You have added to the Gemfile")
      expect(err).to include("* myrack-obama")
      expect(err).not_to include("You have deleted from the Gemfile")
      expect(err).not_to include("You have changed in the Gemfile")
    end

    it "works if a path gem is missing but is in a without group" do
      build_lib "path_gem"
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rake"
        gem "path_gem", :path => "#{lib_path("path_gem-1.0")}", :group => :development
      G
      expect(the_bundle).to include_gems "path_gem 1.0"
      FileUtils.rm_r lib_path("path_gem-1.0")

      bundle "config set --local path .bundle"
      bundle "config set --local without development"
      bundle "config set --local deployment true"
      bundle :install, env: { "DEBUG" => "1" }
      run "puts :WIN"
      expect(out).to eq("WIN")
    end

    it "works if a gem is missing, but it's on a different platform" do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"

        source "https://gem.repo1" do
          gem "rake", platform: :#{not_local_tag}
        end
      G

      bundle :install, env: { "BUNDLE_FROZEN" => "true" }
      expect(last_command).to be_success
    end

    it "shows a good error if a gem is missing from the lockfile" do
      build_repo4 do
        build_gem "foo"
        build_gem "bar"
      end

      gemfile <<-G
        source "https://gem.repo4"

        gem "foo"
        gem "bar"
      G

      lockfile <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            foo (1.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo
          bar

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle :install, env: { "BUNDLE_FROZEN" => "true" }, raise_on_error: false, artifice: "compact_index"
      expect(err).to include("Your lockfile is missing \"bar\", but can't be updated because frozen mode is set")
    end

    it "explodes if a path gem is missing" do
      build_lib "path_gem"
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rake"
        gem "path_gem", :path => "#{lib_path("path_gem-1.0")}", :group => :development
      G
      expect(the_bundle).to include_gems "path_gem 1.0"
      FileUtils.rm_r lib_path("path_gem-1.0")

      bundle "config set --local path .bundle"
      bundle "config set --local deployment true"
      bundle :install, raise_on_error: false
      expect(err).to include("The path `#{lib_path("path_gem-1.0")}` does not exist.")
    end

    it "can have --frozen set via an environment variable" do
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "myrack-obama"
      G

      ENV["BUNDLE_FROZEN"] = "1"
      bundle "install", raise_on_error: false
      expect(err).to include("frozen mode")
      expect(err).to include("You have added to the Gemfile")
      expect(err).to include("* myrack-obama")
      expect(err).not_to include("You have deleted from the Gemfile")
      expect(err).not_to include("You have changed in the Gemfile")
    end

    it "can have --deployment set via an environment variable" do
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "myrack-obama"
      G

      ENV["BUNDLE_DEPLOYMENT"] = "true"
      bundle "install", raise_on_error: false
      expect(err).to include("frozen mode")
      expect(err).to include("You have added to the Gemfile")
      expect(err).to include("* myrack-obama")
      expect(err).not_to include("You have deleted from the Gemfile")
      expect(err).not_to include("You have changed in the Gemfile")
    end

    it "installs gems by default to vendor/bundle when deployment mode is set via an environment variable" do
      ENV["BUNDLE_DEPLOYMENT"] = "true"
      bundle "install"
      expect(out).to include("vendor/bundle")
    end

    it "installs gems to custom path when deployment mode is set via an environment variable " do
      ENV["BUNDLE_DEPLOYMENT"] = "true"
      ENV["BUNDLE_PATH"] = "vendor/bundle2"
      bundle "install"
      expect(out).to include("vendor/bundle2")
    end

    it "can have --frozen set to false via an environment variable" do
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "myrack-obama"
      G

      ENV["BUNDLE_FROZEN"] = "false"
      ENV["BUNDLE_DEPLOYMENT"] = "false"
      bundle "install"
      expect(out).not_to include("frozen mode")
      expect(out).not_to include("You have added to the Gemfile")
      expect(out).not_to include("* myrack-obama")
    end

    it "explodes if you replace a gem and don't check in the lockfile" do
      gemfile <<-G
        source "https://gem.repo1"
        gem "activesupport"
      G

      bundle "config set --local deployment true"
      bundle :install, raise_on_error: false
      expect(err).to include("frozen mode")
      expect(err).to include("You have added to the Gemfile:\n* activesupport\n\n")
      expect(err).to include("You have deleted from the Gemfile:\n* myrack")
      expect(err).not_to include("You have changed in the Gemfile")
    end

    it "explodes if you remove a gem and don't check in the lockfile" do
      gemfile 'source "https://gem.repo1"'

      bundle "config set --local deployment true"
      bundle :install, raise_on_error: false
      expect(err).to include("Some dependencies were deleted")
      expect(err).to include("frozen mode")
      expect(err).to include("You have deleted from the Gemfile:\n* myrack")
      expect(err).not_to include("You have changed in the Gemfile")
    end

    it "explodes if you add a source" do
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "git://hubz.com"
      G

      bundle "config set --local deployment true"
      bundle :install, raise_on_error: false
      expect(err).to include("frozen mode")
      expect(err).not_to include("You have added to the Gemfile")
      expect(err).to include("You have changed in the Gemfile:\n* myrack from `no specified source` to `git://hubz.com`")
    end

    it "explodes if you change a source from git to the default" do
      build_git "myrack"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-1.0")}"
      G

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "config set --local deployment true"
      bundle :install, raise_on_error: false
      expect(err).to include("frozen mode")
      expect(err).not_to include("You have deleted from the Gemfile")
      expect(err).not_to include("You have added to the Gemfile")
      expect(err).to include("You have changed in the Gemfile:\n* myrack from `#{lib_path("myrack-1.0")}` to `no specified source`")
    end

    it "explodes if you change a source from git to the default, in presence of other git sources" do
      build_lib "foo", path: lib_path("myrack/foo")
      build_git "myrack", path: lib_path("myrack")

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack")}"
        gem "foo", :git => "#{lib_path("myrack")}"
      G

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "foo", :git => "#{lib_path("myrack")}"
      G

      bundle "config set --local deployment true"
      bundle :install, raise_on_error: false
      expect(err).to include("frozen mode")
      expect(err).to include("You have changed in the Gemfile:\n* myrack from `#{lib_path("myrack")}` to `no specified source`")
      expect(err).not_to include("You have added to the Gemfile")
      expect(err).not_to include("You have deleted from the Gemfile")
    end

    it "explodes if you change a source from path to git" do
      build_git "myrack", path: lib_path("myrack")

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :path => "#{lib_path("myrack")}"
      G

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "https:/my-git-repo-for-myrack"
      G

      bundle "config set --local frozen true"
      bundle :install, raise_on_error: false
      expect(err).to include("frozen mode")
      expect(err).to include("You have changed in the Gemfile:\n* myrack from `#{lib_path("myrack")}` to `https:/my-git-repo-for-myrack`")
      expect(err).not_to include("You have added to the Gemfile")
      expect(err).not_to include("You have deleted from the Gemfile")
    end

    it "remembers that the bundle is frozen at runtime" do
      bundle :lock

      bundle "config set --local deployment true"

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", "1.0.0"
        gem "myrack-obama"
      G

      run "require 'myrack'", raise_on_error: false
      expect(err).to include <<~E.strip
        The dependencies in your gemfile changed, but the lockfile can't be updated because frozen mode is set (Bundler::ProductionError)

        You have added to the Gemfile:
        * myrack (= 1.0.0)
        * myrack-obama

        You have deleted from the Gemfile:
        * myrack
      E
    end
  end

  context "with path in Gemfile and packed" do
    it "works fine after bundle package and bundle install --local" do
      build_lib "foo", path: lib_path("foo")
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :path => "#{lib_path("foo")}"
      G

      bundle :install
      expect(the_bundle).to include_gems "foo 1.0"

      bundle "config set cache_all true"
      bundle :cache
      expect(bundled_app("vendor/cache/foo")).to be_directory

      bundle "install --local"
      expect(out).to include("Updating files in vendor/cache")

      pristine_system_gems :bundler
      bundle "config set --local deployment true"
      bundle "install --verbose"
      expect(out).not_to include("can't be updated because frozen mode is set")
      expect(out).not_to include("You have added to the Gemfile")
      expect(out).not_to include("You have deleted from the Gemfile")
      expect(out).to include("vendor/cache/foo")
      expect(the_bundle).to include_gems "foo 1.0"
    end
  end
end
