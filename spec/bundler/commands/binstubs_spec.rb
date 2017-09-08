# frozen_string_literal: true
require "spec_helper"

RSpec.describe "bundle binstubs <gem>" do
  context "when the gem exists in the lockfile" do
    it "sets up the binstub" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle "binstubs rack"

      expect(bundled_app("bin/rackup")).to exist
    end

    it "does not install other binstubs" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "rails"
      G

      bundle "binstubs rails"

      expect(bundled_app("bin/rackup")).not_to exist
      expect(bundled_app("bin/rails")).to exist
    end

    it "does install multiple binstubs" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "rails"
      G

      bundle "binstubs rails rack"

      expect(bundled_app("bin/rackup")).to exist
      expect(bundled_app("bin/rails")).to exist
    end

    it "displays an error when used without any gem" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle "binstubs"
      expect(exitstatus).to eq(1) if exitstatus
      expect(out).to include("`bundle binstubs` needs at least one gem to run.")
    end

    it "does not bundle the bundler binary" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
      G

      bundle "binstubs bundler"

      expect(bundled_app("bin/bundle")).not_to exist
      expect(out).to include("Sorry, Bundler can only be run via Rubygems.")
    end

    it "installs binstubs from git gems" do
      FileUtils.mkdir_p(lib_path("foo/bin"))
      FileUtils.touch(lib_path("foo/bin/foo"))
      build_git "foo", "1.0", :path => lib_path("foo") do |s|
        s.executables = %w(foo)
      end
      install_gemfile <<-G
        gem "foo", :git => "#{lib_path("foo")}"
      G

      bundle "binstubs foo"

      expect(bundled_app("bin/foo")).to exist
    end

    it "installs binstubs from path gems" do
      FileUtils.mkdir_p(lib_path("foo/bin"))
      FileUtils.touch(lib_path("foo/bin/foo"))
      build_lib "foo", "1.0", :path => lib_path("foo") do |s|
        s.executables = %w(foo)
      end
      install_gemfile <<-G
        gem "foo", :path => "#{lib_path("foo")}"
      G

      bundle "binstubs foo"

      expect(bundled_app("bin/foo")).to exist
    end

    it "sets correct permissions for binstubs" do
      with_umask(0o002) do
        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "rack"
        G

        bundle "binstubs rack"
        binary = bundled_app("bin/rackup")
        expect(File.stat(binary).mode.to_s(8)).to eq("100775")
      end
    end
  end

  context "when the gem doesn't exist" do
    it "displays an error with correct status" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
      G

      bundle "binstubs doesnt_exist"

      expect(exitstatus).to eq(7) if exitstatus
      expect(out).to include("Could not find gem 'doesnt_exist'.")
    end
  end

  context "--path" do
    it "sets the binstubs dir" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle "binstubs rack --path exec"

      expect(bundled_app("exec/rackup")).to exist
    end

    it "setting is saved for bundle install" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "rails"
      G

      bundle "binstubs rack --path exec"
      bundle :install

      expect(bundled_app("exec/rails")).to exist
    end
  end

  context "after installing with --standalone" do
    before do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G
      bundle "install --standalone"
    end

    it "includes the standalone path" do
      bundle "binstubs rack --standalone"
      standalone_line = File.read(bundled_app("bin/rackup")).each_line.find {|line| line.include? "$:.unshift" }.strip
      expect(standalone_line).to eq %($:.unshift File.expand_path "../../bundle", path.realpath)
    end
  end

  context "when the bin already exists" do
    it "doesn't overwrite and warns" do
      FileUtils.mkdir_p(bundled_app("bin"))
      File.open(bundled_app("bin/rackup"), "wb") do |file|
        file.print "OMG"
      end

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle "binstubs rack"

      expect(bundled_app("bin/rackup")).to exist
      expect(File.read(bundled_app("bin/rackup"))).to eq("OMG")
      expect(out).to include("Skipped rackup")
      expect(out).to include("overwrite skipped stubs, use --force")
    end

    context "when using --force" do
      it "overwrites the binstub" do
        FileUtils.mkdir_p(bundled_app("bin"))
        File.open(bundled_app("bin/rackup"), "wb") do |file|
          file.print "OMG"
        end

        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "rack"
        G

        bundle "binstubs rack --force"

        expect(bundled_app("bin/rackup")).to exist
        expect(File.read(bundled_app("bin/rackup"))).not_to eq("OMG")
      end
    end
  end

  context "when the gem has no bins" do
    it "suggests child gems if they have bins" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack-obama"
      G

      bundle "binstubs rack-obama"
      expect(out).to include("rack-obama has no executables")
      expect(out).to include("rack has: rackup")
    end

    it "works if child gems don't have bins" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "actionpack"
      G

      bundle "binstubs actionpack"
      expect(out).to include("no executables for the gem actionpack")
    end

    it "works if the gem has development dependencies" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "with_development_dependency"
      G

      bundle "binstubs with_development_dependency"
      expect(out).to include("no executables for the gem with_development_dependency")
    end
  end

  context "when BUNDLE_INSTALL is specified" do
    it "performs an automatic bundle install" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle "config auto_install 1"
      bundle "binstubs rack"
      expect(out).to include("Installing rack 1.0.0")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "does nothing when already up to date" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle "config auto_install 1"
      bundle "binstubs rack", :env => { "BUNDLE_INSTALL" => 1 }
      expect(out).not_to include("Installing rack 1.0.0")
    end
  end
end
