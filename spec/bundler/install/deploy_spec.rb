# frozen_string_literal: true
require "spec_helper"

RSpec.describe "install with --deployment or --frozen" do
  before do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G
  end

  it "fails without a lockfile and says that --deployment requires a lock" do
    bundle "install --deployment"
    expect(out).to include("The --deployment flag requires a Gemfile.lock")
  end

  it "fails without a lockfile and says that --frozen requires a lock" do
    bundle "install --frozen"
    expect(out).to include("The --frozen flag requires a Gemfile.lock")
  end

  it "disallows --deployment --system" do
    bundle "install --deployment --system"
    expect(out).to include("You have specified both --deployment")
    expect(out).to include("Please choose only one option")
    expect(exitstatus).to eq(15) if exitstatus
  end

  it "disallows --deployment --path --system" do
    bundle "install --deployment --path . --system"
    expect(out).to include("You have specified both --path")
    expect(out).to include("as well as --system")
    expect(out).to include("Please choose only one option")
    expect(exitstatus).to eq(15) if exitstatus
  end

  it "works after you try to deploy without a lock" do
    bundle "install --deployment"
    bundle :install
    expect(exitstatus).to eq(0) if exitstatus
    expect(the_bundle).to include_gems "rack 1.0"
  end

  it "still works if you are not in the app directory and specify --gemfile" do
    bundle "install"
    Dir.chdir tmp
    simulate_new_machine
    bundle "install --gemfile #{tmp}/bundled_app/Gemfile --deployment"
    Dir.chdir bundled_app
    expect(the_bundle).to include_gems "rack 1.0"
  end

  it "works if you exclude a group with a git gem" do
    build_git "foo"
    gemfile <<-G
      group :test do
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      end
    G
    bundle :install
    bundle "install --deployment --without test"
    expect(exitstatus).to eq(0) if exitstatus
  end

  it "works when you bundle exec bundle" do
    bundle :install
    bundle "install --deployment"
    bundle "exec bundle check"
    expect(exitstatus).to eq(0) if exitstatus
  end

  it "works when using path gems from the same path and the version is specified" do
    build_lib "foo", :path => lib_path("nested/foo")
    build_lib "bar", :path => lib_path("nested/bar")
    gemfile <<-G
      gem "foo", "1.0", :path => "#{lib_path("nested")}"
      gem "bar", :path => "#{lib_path("nested")}"
    G

    bundle! :install
    bundle! "install --deployment"
  end

  it "works when there are credentials in the source URL" do
    install_gemfile(<<-G, :artifice => "endpoint_strict_basic_authentication", :quiet => true)
      source "http://user:pass@localgemserver.test/"

      gem "rack-obama", ">= 1.0"
    G

    bundle "install --deployment", :artifice => "endpoint_strict_basic_authentication"

    expect(exitstatus).to eq(0) if exitstatus
  end

  it "works with sources given by a block" do
    install_gemfile <<-G
      source "file://#{gem_repo1}" do
        gem "rack"
      end
    G

    bundle "install --deployment"

    expect(exitstatus).to eq(0) if exitstatus
    expect(the_bundle).to include_gems "rack 1.0"
  end

  describe "with an existing lockfile" do
    before do
      bundle "install"
    end

    it "works with the --deployment flag if you didn't change anything" do
      bundle "install --deployment"
      expect(exitstatus).to eq(0) if exitstatus
    end

    it "works with the --frozen flag if you didn't change anything" do
      bundle "install --frozen"
      expect(exitstatus).to eq(0) if exitstatus
    end

    it "explodes with the --deployment flag if you make a change and don't check in the lockfile" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "rack-obama"
      G

      bundle "install --deployment"
      expect(out).to include("deployment mode")
      expect(out).to include("You have added to the Gemfile")
      expect(out).to include("* rack-obama")
      expect(out).not_to include("You have deleted from the Gemfile")
      expect(out).not_to include("You have changed in the Gemfile")
    end

    it "can have --frozen set via an environment variable" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "rack-obama"
      G

      ENV["BUNDLE_FROZEN"] = "1"
      bundle "install"
      expect(out).to include("deployment mode")
      expect(out).to include("You have added to the Gemfile")
      expect(out).to include("* rack-obama")
      expect(out).not_to include("You have deleted from the Gemfile")
      expect(out).not_to include("You have changed in the Gemfile")
    end

    it "can have --frozen set to false via an environment variable" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "rack-obama"
      G

      ENV["BUNDLE_FROZEN"] = "false"
      bundle "install"
      expect(out).not_to include("deployment mode")
      expect(out).not_to include("You have added to the Gemfile")
      expect(out).not_to include("* rack-obama")
    end

    it "explodes with the --frozen flag if you make a change and don't check in the lockfile" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "rack-obama", "1.1"
      G

      bundle "install --frozen"
      expect(out).to include("deployment mode")
      expect(out).to include("You have added to the Gemfile")
      expect(out).to include("* rack-obama (= 1.1)")
      expect(out).not_to include("You have deleted from the Gemfile")
      expect(out).not_to include("You have changed in the Gemfile")
    end

    it "explodes if you remove a gem and don't check in the lockfile" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "activesupport"
      G

      bundle "install --deployment"
      expect(out).to include("deployment mode")
      expect(out).to include("You have added to the Gemfile:\n* activesupport\n\n")
      expect(out).to include("You have deleted from the Gemfile:\n* rack")
      expect(out).not_to include("You have changed in the Gemfile")
    end

    it "explodes if you add a source" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "git://hubz.com"
      G

      bundle "install --deployment"
      expect(out).to include("deployment mode")
      expect(out).to include("You have added to the Gemfile:\n* source: git://hubz.com (at master)")
      expect(out).not_to include("You have changed in the Gemfile")
    end

    it "explodes if you unpin a source" do
      build_git "rack"

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-1.0")}"
      G

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle "install --deployment"
      expect(out).to include("deployment mode")
      expect(out).to include("You have deleted from the Gemfile:\n* source: #{lib_path("rack-1.0")} (at master@#{revision_for(lib_path("rack-1.0"))[0..6]}")
      expect(out).not_to include("You have added to the Gemfile")
      expect(out).not_to include("You have changed in the Gemfile")
    end

    it "explodes if you unpin a source, leaving it pinned somewhere else" do
      build_lib "foo", :path => lib_path("rack/foo")
      build_git "rack", :path => lib_path("rack")

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack")}"
        gem "foo", :git => "#{lib_path("rack")}"
      G

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "foo", :git => "#{lib_path("rack")}"
      G

      bundle "install --deployment"
      expect(out).to include("deployment mode")
      expect(out).to include("You have changed in the Gemfile:\n* rack from `no specified source` to `#{lib_path("rack")} (at master@#{revision_for(lib_path("rack"))[0..6]})`")
      expect(out).not_to include("You have added to the Gemfile")
      expect(out).not_to include("You have deleted from the Gemfile")
    end

    it "remembers that the bundle is frozen at runtime" do
      bundle "install --deployment"

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", "1.0.0"
        gem "rack-obama"
      G

      expect(the_bundle).not_to include_gems "rack 1.0.0"
      expect(err).to include strip_whitespace(<<-E).strip
The dependencies in your gemfile changed

You have added to the Gemfile:
* rack (= 1.0.0)
* rack-obama

You have deleted from the Gemfile:
* rack
      E
    end
  end

  context "with path in Gemfile and packed" do
    it "works fine after bundle package and bundle install --local" do
      build_lib "foo", :path => lib_path("foo")
      install_gemfile! <<-G
        gem "foo", :path => "#{lib_path("foo")}"
      G

      bundle! :install
      expect(the_bundle).to include_gems "foo 1.0"
      bundle! "package --all"
      expect(bundled_app("vendor/cache/foo")).to be_directory

      bundle! "install --local"
      expect(out).to include("Using foo 1.0 from source at")
      expect(out).to include("vendor/cache/foo")

      simulate_new_machine
      bundle! "install --deployment --verbose"
      expect(out).not_to include("You are trying to install in deployment mode after changing your Gemfile")
      expect(out).not_to include("You have added to the Gemfile")
      expect(out).not_to include("You have deleted from the Gemfile")
      expect(out).to include("Using foo 1.0 from source at")
      expect(out).to include("vendor/cache/foo")
      expect(the_bundle).to include_gems "foo 1.0"
    end
  end
end
