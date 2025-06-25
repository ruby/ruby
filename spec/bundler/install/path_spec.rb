# frozen_string_literal: true

RSpec.describe "bundle install" do
  describe "with path configured" do
    before :each do
      build_gem "myrack", "1.0.0", to_system: true do |s|
        s.write "lib/myrack.rb", "puts 'FAIL'"
      end

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
    end

    it "does not use available system gems with `vendor/bundle" do
      bundle "config set --local path vendor/bundle"
      bundle :install
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "uses system gems with `path.system` configured with more priority than `path`" do
      bundle "config set --local path.system true"
      bundle "config set --global path vendor/bundle"
      bundle :install
      run "require 'myrack'", raise_on_error: false
      expect(out).to include("FAIL")
    end

    it "handles paths with regex characters in them" do
      dir = bundled_app("bun++dle")
      dir.mkpath

      bundle "config set --local path #{dir.join("vendor/bundle")}"
      bundle :install, dir: dir
      expect(out).to include("installed into `./vendor/bundle`")

      dir.rmtree
    end

    it "prints a message to let the user know where gems where installed" do
      bundle "config set --local path vendor/bundle"
      bundle :install
      expect(out).to include("gems are installed into `./vendor/bundle`")
    end

    it "disallows --path vendor/bundle --system" do
      bundle "install --path vendor/bundle --system", raise_on_error: false
      expect(err).to include("Please choose only one option.")
      expect(exitstatus).to eq(15)
    end

    it "remembers to disable system gems after the first time with bundle --path vendor/bundle" do
      bundle "install --path vendor/bundle"
      FileUtils.rm_r bundled_app("vendor")
      bundle "install"

      expect(vendored_gems("gems/myrack-1.0.0")).to be_directory
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    context "with path_relative_to_cwd set to true" do
      before { bundle "config set path_relative_to_cwd true" }

      it "installs the bundle relatively to current working directory" do
        bundle "install --gemfile='#{bundled_app}/Gemfile' --path vendor/bundle", dir: bundled_app.parent
        expect(out).to include("installed into `./vendor/bundle`")
        expect(bundled_app("../vendor/bundle")).to be_directory
        expect(the_bundle).to include_gems "myrack 1.0.0"
      end

      it "installs the standalone bundle relative to the cwd" do
        bundle :install, gemfile: bundled_app_gemfile, standalone: true, dir: bundled_app.parent
        expect(out).to include("installed into `./bundled_app/bundle`")
        expect(bundled_app("bundle")).to be_directory
        expect(bundled_app("bundle/ruby")).to be_directory

        bundle "config unset path"

        bundle :install, gemfile: bundled_app_gemfile, standalone: true, dir: bundled_app("subdir").tap(&:mkpath)
        expect(out).to include("installed into `../bundle`")
        expect(bundled_app("bundle")).to be_directory
        expect(bundled_app("bundle/ruby")).to be_directory
      end
    end
  end

  describe "when BUNDLE_PATH or the global path config is set" do
    before :each do
      build_lib "myrack", "1.0.0", to_system: true do |s|
        s.write "lib/myrack.rb", "raise 'FAIL'"
      end

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
    end

    def set_bundle_path(type, location)
      if type == :env
        ENV["BUNDLE_PATH"] = location
      elsif type == :global
        bundle "config set path #{location}", "no-color" => nil
      end
    end

    [:env, :global].each do |type|
      context "when set via #{type}" do
        it "installs gems to a path if one is specified" do
          set_bundle_path(type, bundled_app("vendor2").to_s)
          bundle "config set --local path vendor/bundle"
          bundle :install

          expect(vendored_gems("gems/myrack-1.0.0")).to be_directory
          expect(bundled_app("vendor2")).not_to be_directory
          expect(the_bundle).to include_gems "myrack 1.0.0"
        end

        it "installs gems to ." do
          set_bundle_path(type, ".")
          bundle "config set --global disable_shared_gems true"

          bundle :install

          paths_to_exist = %w[cache/myrack-1.0.0.gem gems/myrack-1.0.0 specifications/myrack-1.0.0.gemspec].map {|path| bundled_app(Bundler.ruby_scope, path) }
          expect(paths_to_exist).to all exist
          expect(the_bundle).to include_gems "myrack 1.0.0"
        end

        it "installs gems to the path" do
          set_bundle_path(type, bundled_app("vendor").to_s)

          bundle :install

          expect(bundled_app("vendor", Bundler.ruby_scope, "gems/myrack-1.0.0")).to be_directory
          expect(the_bundle).to include_gems "myrack 1.0.0"
        end

        it "installs gems to the path relative to root when relative" do
          set_bundle_path(type, "vendor")

          FileUtils.mkdir_p bundled_app("lol")
          bundle :install, dir: bundled_app("lol")

          expect(bundled_app("vendor", Bundler.ruby_scope, "gems/myrack-1.0.0")).to be_directory
          expect(the_bundle).to include_gems "myrack 1.0.0"
        end
      end
    end

    it "installs gems to BUNDLE_PATH from .bundle/config" do
      config "BUNDLE_PATH" => bundled_app("vendor/bundle").to_s

      bundle :install

      expect(vendored_gems("gems/myrack-1.0.0")).to be_directory
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "sets BUNDLE_PATH as the first argument to bundle install" do
      bundle "config set --local path ./vendor/bundle"
      bundle :install

      expect(vendored_gems("gems/myrack-1.0.0")).to be_directory
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "disables system gems when passing a path to install" do
      # This is so that vendored gems can be distributed to others
      build_gem "myrack", "1.1.0", to_system: true
      bundle "config set --local path ./vendor/bundle"
      bundle :install

      expect(vendored_gems("gems/myrack-1.0.0")).to be_directory
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "re-installs gems whose extensions have been deleted" do
      build_lib "very_simple_binary", "1.0.0", to_system: true do |s|
        s.write "lib/very_simple_binary.rb", "raise 'FAIL'"
      end

      gemfile <<-G
        source "https://gem.repo1"
        gem "very_simple_binary"
      G

      bundle "config set --local path ./vendor/bundle"
      bundle :install

      expect(vendored_gems("gems/very_simple_binary-1.0")).to be_directory
      expect(vendored_gems("extensions")).to be_directory
      expect(the_bundle).to include_gems "very_simple_binary 1.0", source: "remote1"

      vendored_gems("extensions").rmtree

      run "require 'very_simple_binary_c'", raise_on_error: false
      expect(err).to include("Bundler::GemNotFound")

      bundle "config set --local path ./vendor/bundle"
      bundle :install

      expect(vendored_gems("gems/very_simple_binary-1.0")).to be_directory
      expect(vendored_gems("extensions")).to be_directory
      expect(the_bundle).to include_gems "very_simple_binary 1.0", source: "remote1"
    end
  end

  describe "to a file" do
    before do
      FileUtils.touch bundled_app("bundle")
    end

    it "reports the file exists" do
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "config set --local path bundle"
      bundle :install, raise_on_error: false
      expect(err).to include("file already exists")
    end
  end
end
