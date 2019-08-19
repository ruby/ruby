# frozen_string_literal: true

RSpec.describe "bundle install" do
  describe "with --path" do
    before :each do
      build_gem "rack", "1.0.0", :to_system => true do |s|
        s.write "lib/rack.rb", "puts 'FAIL'"
      end

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G
    end

    it "does not use available system gems with bundle --path vendor/bundle", :bundler => "< 3" do
      bundle! :install, forgotten_command_line_options(:path => "vendor/bundle")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "handles paths with regex characters in them" do
      dir = bundled_app("bun++dle")
      dir.mkpath

      Dir.chdir(dir) do
        bundle! :install, forgotten_command_line_options(:path => dir.join("vendor/bundle"))
        expect(out).to include("installed into `./vendor/bundle`")
      end

      dir.rmtree
    end

    it "prints a warning to let the user know what has happened with bundle --path vendor/bundle" do
      bundle! :install, forgotten_command_line_options(:path => "vendor/bundle")
      expect(out).to include("gems are installed into `./vendor/bundle`")
    end

    it "disallows --path vendor/bundle --system", :bundler => "< 3" do
      bundle "install --path vendor/bundle --system"
      expect(out).to include("Please choose only one option.")
      expect(exitstatus).to eq(15) if exitstatus
    end

    it "remembers to disable system gems after the first time with bundle --path vendor/bundle", :bundler => "< 3" do
      bundle "install --path vendor/bundle"
      FileUtils.rm_rf bundled_app("vendor")
      bundle "install"

      expect(vendored_gems("gems/rack-1.0.0")).to be_directory
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    context "with path_relative_to_cwd set to true" do
      before { bundle! "config path_relative_to_cwd true" }

      it "installs the bundle relatively to current working directory", :bundler => "< 3" do
        Dir.chdir(bundled_app.parent) do
          bundle! "install --gemfile='#{bundled_app}/Gemfile' --path vendor/bundle"
          expect(out).to include("installed into `./vendor/bundle`")
          expect(bundled_app("../vendor/bundle")).to be_directory
        end
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "installs the standalone bundle relative to the cwd" do
        Dir.chdir(bundled_app.parent) do
          bundle! :install, :gemfile => bundled_app("Gemfile"), :standalone => true
          expect(out).to include("installed into `./bundled_app/bundle`")
          expect(bundled_app("bundle")).to be_directory
          expect(bundled_app("bundle/ruby")).to be_directory
        end

        bundle! "config unset path"

        Dir.chdir(bundled_app("subdir").tap(&:mkpath)) do
          bundle! :install, :gemfile => bundled_app("Gemfile"), :standalone => true
          expect(out).to include("installed into `../bundle`")
          expect(bundled_app("bundle")).to be_directory
          expect(bundled_app("bundle/ruby")).to be_directory
        end
      end
    end
  end

  describe "when BUNDLE_PATH or the global path config is set" do
    before :each do
      build_lib "rack", "1.0.0", :to_system => true do |s|
        s.write "lib/rack.rb", "raise 'FAIL'"
      end

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G
    end

    def set_bundle_path(type, location)
      if type == :env
        ENV["BUNDLE_PATH"] = location
      elsif type == :global
        bundle! "config path #{location}", "no-color" => nil
      end
    end

    [:env, :global].each do |type|
      context "when set via #{type}" do
        it "installs gems to a path if one is specified" do
          set_bundle_path(type, bundled_app("vendor2").to_s)
          bundle! :install, forgotten_command_line_options(:path => "vendor/bundle")

          expect(vendored_gems("gems/rack-1.0.0")).to be_directory
          expect(bundled_app("vendor2")).not_to be_directory
          expect(the_bundle).to include_gems "rack 1.0.0"
        end

        context "with global_path_appends_ruby_scope set", :bundler => "3" do
          it "installs gems to ." do
            set_bundle_path(type, ".")
            bundle! "config --global disable_shared_gems true"

            bundle! :install

            paths_to_exist = %w[cache/rack-1.0.0.gem gems/rack-1.0.0 specifications/rack-1.0.0.gemspec].map {|path| bundled_app(Bundler.ruby_scope, path) }
            expect(paths_to_exist).to all exist
            expect(the_bundle).to include_gems "rack 1.0.0"
          end

          it "installs gems to the path" do
            set_bundle_path(type, bundled_app("vendor").to_s)

            bundle! :install

            expect(bundled_app("vendor", Bundler.ruby_scope, "gems/rack-1.0.0")).to be_directory
            expect(the_bundle).to include_gems "rack 1.0.0"
          end

          it "installs gems to the path relative to root when relative" do
            set_bundle_path(type, "vendor")

            FileUtils.mkdir_p bundled_app("lol")
            Dir.chdir(bundled_app("lol")) do
              bundle! :install
            end

            expect(bundled_app("vendor", Bundler.ruby_scope, "gems/rack-1.0.0")).to be_directory
            expect(the_bundle).to include_gems "rack 1.0.0"
          end
        end

        context "with global_path_appends_ruby_scope unset", :bundler => "< 3" do
          it "installs gems to ." do
            set_bundle_path(type, ".")
            bundle! "config --global disable_shared_gems true"

            bundle! :install

            expect([bundled_app("cache/rack-1.0.0.gem"), bundled_app("gems/rack-1.0.0"), bundled_app("specifications/rack-1.0.0.gemspec")]).to all exist
            expect(the_bundle).to include_gems "rack 1.0.0"
          end

          it "installs gems to BUNDLE_PATH with #{type}" do
            set_bundle_path(type, bundled_app("vendor").to_s)

            bundle :install

            expect(bundled_app("vendor/gems/rack-1.0.0")).to be_directory
            expect(the_bundle).to include_gems "rack 1.0.0"
          end

          it "installs gems to BUNDLE_PATH relative to root when relative" do
            set_bundle_path(type, "vendor")

            FileUtils.mkdir_p bundled_app("lol")
            Dir.chdir(bundled_app("lol")) do
              bundle :install
            end

            expect(bundled_app("vendor/gems/rack-1.0.0")).to be_directory
            expect(the_bundle).to include_gems "rack 1.0.0"
          end
        end
      end
    end

    it "installs gems to BUNDLE_PATH from .bundle/config" do
      config "BUNDLE_PATH" => bundled_app("vendor/bundle").to_s

      bundle :install

      expect(vendored_gems("gems/rack-1.0.0")).to be_directory
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "sets BUNDLE_PATH as the first argument to bundle install" do
      bundle! :install, forgotten_command_line_options(:path => "./vendor/bundle")

      expect(vendored_gems("gems/rack-1.0.0")).to be_directory
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "disables system gems when passing a path to install" do
      # This is so that vendored gems can be distributed to others
      build_gem "rack", "1.1.0", :to_system => true
      bundle! :install, forgotten_command_line_options(:path => "./vendor/bundle")

      expect(vendored_gems("gems/rack-1.0.0")).to be_directory
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "re-installs gems whose extensions have been deleted", :ruby_repo, :rubygems => ">= 2.3" do
      build_lib "very_simple_binary", "1.0.0", :to_system => true do |s|
        s.write "lib/very_simple_binary.rb", "raise 'FAIL'"
      end

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "very_simple_binary"
      G

      bundle! :install, forgotten_command_line_options(:path => "./vendor/bundle")

      expect(vendored_gems("gems/very_simple_binary-1.0")).to be_directory
      expect(vendored_gems("extensions")).to be_directory
      expect(the_bundle).to include_gems "very_simple_binary 1.0", :source => "remote1"

      vendored_gems("extensions").rmtree

      run "require 'very_simple_binary_c'"
      expect(err).to include("Bundler::GemNotFound")

      bundle :install, forgotten_command_line_options(:path => "./vendor/bundle")

      expect(vendored_gems("gems/very_simple_binary-1.0")).to be_directory
      expect(vendored_gems("extensions")).to be_directory
      expect(the_bundle).to include_gems "very_simple_binary 1.0", :source => "remote1"
    end
  end

  describe "to a file" do
    before do
      in_app_root do
        FileUtils.touch "bundle"
      end
    end

    it "reports the file exists" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle :install, forgotten_command_line_options(:path => "bundle")
      expect(out).to include("file already exists")
    end
  end
end
