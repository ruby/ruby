# frozen_string_literal: true

RSpec.describe "bundle binstubs <gem>" do
  context "when the gem exists in the lockfile" do
    it "sets up the binstub" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "binstubs myrack"

      expect(bundled_app("bin/myrackup")).to exist
    end

    it "does not install other binstubs" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "rails"
      G

      bundle "binstubs rails"

      expect(bundled_app("bin/myrackup")).not_to exist
      expect(bundled_app("bin/rails")).to exist
    end

    it "does install multiple binstubs" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "rails"
      G

      bundle "binstubs rails myrack"

      expect(bundled_app("bin/myrackup")).to exist
      expect(bundled_app("bin/rails")).to exist
    end

    it "allows installing all binstubs" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rails"
      G

      bundle :binstubs, all: true

      expect(bundled_app("bin/rails")).to exist
      expect(bundled_app("bin/rake")).to exist
    end

    it "allows installing binstubs for all platforms" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "binstubs myrack --all-platforms"

      expect(bundled_app("bin/myrackup")).to exist
      expect(bundled_app("bin/myrackup.cmd")).to exist
    end

    it "displays an error when used without any gem" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "binstubs", raise_on_error: false
      expect(exitstatus).to eq(1)
      expect(err).to include("`bundle binstubs` needs at least one gem to run.")
    end

    it "displays an error when used with --all and gems" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "binstubs myrack", all: true, raise_on_error: false
      expect(last_command).to be_failure
      expect(err).to include("Cannot specify --all with specific gems")
    end

    it "installs binstubs from git gems" do
      FileUtils.mkdir_p(lib_path("foo/bin"))
      FileUtils.touch(lib_path("foo/bin/foo"))
      build_git "foo", "1.0", path: lib_path("foo") do |s|
        s.executables = %w[foo]
      end
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo")}"
      G

      bundle "binstubs foo"

      expect(bundled_app("bin/foo")).to exist
    end

    it "installs binstubs from path gems" do
      FileUtils.mkdir_p(lib_path("foo/bin"))
      FileUtils.touch(lib_path("foo/bin/foo"))
      build_lib "foo", "1.0", path: lib_path("foo") do |s|
        s.executables = %w[foo]
      end
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :path => "#{lib_path("foo")}"
      G

      bundle "binstubs foo"

      expect(bundled_app("bin/foo")).to exist
    end

    it "sets correct permissions for binstubs" do
      with_umask(0o002) do
        install_gemfile <<-G
          source "https://gem.repo1"
          gem "myrack"
        G

        bundle "binstubs myrack"
        binary = bundled_app("bin/myrackup")
        expect(File.stat(binary).mode.to_s(8)).to eq(Gem.win_platform? ? "100644" : "100775")
      end
    end

    context "when using --shebang" do
      it "sets the specified shebang for the binstub" do
        install_gemfile <<-G
          source "https://gem.repo1"
          gem "myrack"
        G

        bundle "binstubs myrack --shebang jruby"
        expect(File.readlines(bundled_app("bin/myrackup")).first).to eq("#!/usr/bin/env jruby\n")
      end
    end
  end

  context "when the gem doesn't exist" do
    it "displays an error with correct status" do
      install_gemfile <<-G
        source "https://gem.repo1"
      G

      bundle "binstubs doesnt_exist", raise_on_error: false

      expect(exitstatus).to eq(7)
      expect(err).to include("Could not find gem 'doesnt_exist'.")
    end
  end

  context "--path" do
    it "sets the binstubs dir" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "binstubs myrack --path exec"

      expect(bundled_app("exec/myrackup")).to exist
    end

    it "setting is saved for bundle install", bundler: "2" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "rails"
      G

      bundle "binstubs myrack", path: "exec"
      bundle :install

      expect(bundled_app("exec/rails")).to exist
    end
  end

  context "with --standalone option" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "rails"
      G
    end

    it "generates a standalone binstub" do
      bundle "binstubs myrack --standalone"
      expect(bundled_app("bin/myrackup")).to exist
    end

    it "generates a binstub that does not depend on rubygems or bundler" do
      bundle "binstubs myrack --standalone"
      expect(File.read(bundled_app("bin/myrackup"))).to_not include("Gem.bin_path")
    end

    context "when specified --path option" do
      it "generates a standalone binstub at the given path" do
        bundle "binstubs myrack --standalone --path foo"
        expect(bundled_app("foo/myrackup")).to exist
      end
    end

    context "when specified --all-platforms option" do
      it "generates standalone binstubs for all platforms" do
        bundle "binstubs myrack --standalone --all-platforms"
        expect(bundled_app("bin/myrackup")).to exist
        expect(bundled_app("bin/myrackup.cmd")).to exist
      end
    end

    context "when the gem is bundler" do
      it "warns without generating a standalone binstub" do
        bundle "binstubs bundler --standalone"
        expect(bundled_app("bin/bundle")).not_to exist
        expect(bundled_app("bin/bundler")).not_to exist
        expect(err).to include("Sorry, Bundler can only be run via RubyGems.")
      end
    end

    context "when specified --all option" do
      it "generates standalone binstubs for all gems except bundler" do
        bundle "binstubs --standalone --all"
        expect(bundled_app("bin/myrackup")).to exist
        expect(bundled_app("bin/rails")).to exist
        expect(bundled_app("bin/bundle")).not_to exist
        expect(bundled_app("bin/bundler")).not_to exist
        expect(err).not_to include("Sorry, Bundler can only be run via RubyGems.")
      end
    end
  end

  context "when the bin already exists" do
    it "doesn't overwrite and warns" do
      FileUtils.mkdir_p(bundled_app("bin"))
      File.open(bundled_app("bin/myrackup"), "wb") do |file|
        file.print "OMG"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "binstubs myrack"

      expect(bundled_app("bin/myrackup")).to exist
      expect(File.read(bundled_app("bin/myrackup"))).to eq("OMG")
      expect(err).to include("Skipped myrackup")
      expect(err).to include("overwrite skipped stubs, use --force")
    end

    context "when using --force" do
      it "overwrites the binstub" do
        FileUtils.mkdir_p(bundled_app("bin"))
        File.open(bundled_app("bin/myrackup"), "wb") do |file|
          file.print "OMG"
        end

        install_gemfile <<-G
          source "https://gem.repo1"
          gem "myrack"
        G

        bundle "binstubs myrack --force"

        expect(bundled_app("bin/myrackup")).to exist
        expect(File.read(bundled_app("bin/myrackup"))).not_to eq("OMG")
      end
    end
  end

  context "when the gem has no bins" do
    it "suggests child gems if they have bins" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack-obama"
      G

      bundle "binstubs myrack-obama"
      expect(err).to include("myrack-obama has no executables")
      expect(err).to include("myrack has: myrackup")
    end

    it "works if child gems don't have bins" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "actionpack"
      G

      bundle "binstubs actionpack"
      expect(err).to include("no executables for the gem actionpack")
    end

    it "works if the gem has development dependencies" do
      build_repo2 do
        build_gem "with_development_dependency" do |s|
          s.add_development_dependency "activesupport", "= 2.3.5"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "with_development_dependency"
      G

      bundle "binstubs with_development_dependency"
      expect(err).to include("no executables for the gem with_development_dependency")
    end
  end

  context "when BUNDLE_INSTALL is specified" do
    it "performs an automatic bundle install" do
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "config set auto_install 1"
      bundle "binstubs myrack"
      expect(out).to include("Installing myrack 1.0.0")
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "does nothing when already up to date" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "config set auto_install 1"
      bundle "binstubs myrack", env: { "BUNDLE_INSTALL" => "1" }
      expect(out).not_to include("Installing myrack 1.0.0")
    end
  end
end
