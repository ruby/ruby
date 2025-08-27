# frozen_string_literal: true

RSpec.describe "bundle install with gem sources" do
  describe "the simple case" do
    it "prints output and returns if no dependencies are specified" do
      gemfile <<-G
        source "https://gem.repo1"
      G

      bundle :install
      expect(err).to match(/no dependencies/)
    end

    it "does not make a lockfile if the install fails" do
      install_gemfile <<-G, raise_on_error: false
        raise StandardError, "FAIL"
      G

      expect(err).to include('StandardError, "FAIL"')
      expect(bundled_app_lock).not_to exist
    end

    it "creates a Gemfile.lock" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      expect(bundled_app_lock).to exist
    end

    it "does not create ./.bundle by default" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      expect(bundled_app(".bundle")).not_to exist
    end

    it "will create a ./.bundle by default", bundler: "5" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      expect(bundled_app(".bundle")).to exist
    end

    it "does not create ./.bundle by default when installing to system gems" do
      install_gemfile <<-G, env: { "BUNDLE_PATH__SYSTEM" => "true" }
        source "https://gem.repo1"
        gem "myrack"
      G

      expect(bundled_app(".bundle")).not_to exist
    end

    it "creates lockfiles based on the Gemfile name" do
      gemfile bundled_app("OmgFile"), <<-G
        source "https://gem.repo1"
        gem "myrack", "1.0"
      G

      bundle "install --gemfile OmgFile"

      expect(bundled_app("OmgFile.lock")).to exist
    end

    it "doesn't delete the lockfile if one already exists" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G

      lockfile = File.read(bundled_app_lock)

      install_gemfile <<-G, raise_on_error: false
        raise StandardError, "FAIL"
      G

      expect(File.read(bundled_app_lock)).to eq(lockfile)
    end

    it "does not touch the lockfile if nothing changed" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      expect { run "1" }.not_to change { File.mtime(bundled_app_lock) }
    end

    it "fetches gems" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G

      expect(default_bundle_path("gems/myrack-1.0.0")).to exist
      expect(the_bundle).to include_gems("myrack 1.0.0")
    end

    it "auto-heals missing gems" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G

      FileUtils.rm_r(default_bundle_path("gems/myrack-1.0.0"))

      bundle "install --verbose"

      expect(out).to include("Installing myrack 1.0.0")
      expect(default_bundle_path("gems/myrack-1.0.0")).to exist
      expect(the_bundle).to include_gems("myrack 1.0.0")
    end

    it "does not state that it's constantly reinstalling empty gems" do
      build_repo4 do
        build_gem "empty", "1.0.0", no_default: true, allowed_warning: "no files specified"
      end

      install_gemfile <<~G
        source "https://gem.repo4"

        gem "empty"
      G
      gem_dir = default_bundle_path("gems/empty-1.0.0")
      expect(gem_dir).to be_empty

      bundle "install --verbose"
      expect(out).not_to include("Installing empty")
    end

    it "fetches gems when multiple versions are specified" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack', "> 0.9", "< 1.0"
      G

      expect(default_bundle_path("gems/myrack-0.9.1")).to exist
      expect(the_bundle).to include_gems("myrack 0.9.1")
    end

    it "fetches gems when multiple versions are specified take 2" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack', "< 1.0", "> 0.9"
      G

      expect(default_bundle_path("gems/myrack-0.9.1")).to exist
      expect(the_bundle).to include_gems("myrack 0.9.1")
    end

    it "raises an appropriate error when gems are specified using symbols" do
      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo1"
        gem :myrack
      G
      expect(exitstatus).to eq(4)
    end

    it "pulls in dependencies" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rails"
      G

      expect(the_bundle).to include_gems "actionpack 2.3.2", "rails 2.3.2"
    end

    it "does the right version" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", "0.9.1"
      G

      expect(the_bundle).to include_gems "myrack 0.9.1"
    end

    it "does not install the development dependency" do
      build_repo2 do
        build_gem "with_development_dependency" do |s|
          s.add_development_dependency "activesupport", "= 2.3.5"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "with_development_dependency"
      G

      expect(the_bundle).to include_gems("with_development_dependency 1.0.0").
        and not_include_gems("activesupport 2.3.5")
    end

    it "resolves correctly" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "activemerchant"
        gem "rails"
      G

      expect(the_bundle).to include_gems "activemerchant 1.0", "activesupport 2.3.2", "actionpack 2.3.2"
    end

    it "activates gem correctly according to the resolved gems" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "activesupport", "2.3.5"
      G

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "activemerchant"
        gem "rails"
      G

      expect(the_bundle).to include_gems "activemerchant 1.0", "activesupport 2.3.2", "actionpack 2.3.2"
    end

    it "does not reinstall any gem that is already available locally" do
      system_gems "activesupport-2.3.2", path: default_bundle_path

      build_repo2 do
        build_gem "activesupport", "2.3.2" do |s|
          s.write "lib/activesupport.rb", "ACTIVESUPPORT = 'fail'"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activerecord", "2.3.2"
      G

      expect(the_bundle).to include_gems "activesupport 2.3.2"
    end

    it "works when the gemfile specifies gems that only exist in the system" do
      build_gem "foo", to_bundle: true
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "foo"
      G

      expect(the_bundle).to include_gems "myrack 1.0.0", "foo 1.0.0"
    end

    it "prioritizes local gems over remote gems" do
      build_gem "myrack", "9.0.0", to_bundle: true

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      expect(the_bundle).to include_gems "myrack 9.0.0"
    end

    it "loads env plugins" do
      plugin_msg = "hello from an env plugin!"
      create_file "plugins/rubygems_plugin.rb", "puts '#{plugin_msg}'"
      install_gemfile <<-G, env: { "RUBYLIB" => rubylib.unshift(bundled_app("plugins").to_s).join(File::PATH_SEPARATOR) }
        source "https://gem.repo1"
        gem "myrack"
      G

      expect(stdboth).to include(plugin_msg)
    end

    describe "with a gem that installs multiple platforms" do
      it "installs gems for the local platform as first choice" do
        simulate_platform "x86-darwin-100" do
          install_gemfile <<-G
            source "https://gem.repo1"
            gem "platform_specific"
          G

          expect(the_bundle).to include_gems("platform_specific 1.0 x86-darwin-100")
        end
      end

      it "falls back on plain ruby" do
        simulate_platform "foo-bar-baz" do
          install_gemfile <<-G
            source "https://gem.repo1"
            gem "platform_specific"
          G

          expect(the_bundle).to include_gems("platform_specific 1.0 ruby")
        end
      end

      it "installs gems for java" do
        simulate_platform "java" do
          install_gemfile <<-G
            source "https://gem.repo1"
            gem "platform_specific"
          G

          expect(the_bundle).to include_gems("platform_specific 1.0 java")
        end
      end

      it "installs gems for windows" do
        simulate_platform "x86-mswin32" do
          install_gemfile <<-G
            source "https://gem.repo1"
            gem "platform_specific"
          G

          expect(the_bundle).to include_gems("platform_specific 1.0 x86-mswin32")
        end
      end

      it "installs gems for aarch64-mingw-ucrt" do
        simulate_platform "aarch64-mingw-ucrt" do
          install_gemfile <<-G
            source "https://gem.repo1"
            gem "platform_specific"
          G
        end

        expect(out).to include("Installing platform_specific 1.0 (aarch64-mingw-ucrt)")
      end
    end

    describe "doing bundle install foo" do
      before do
        gemfile <<-G
          source "https://gem.repo1"
          gem "myrack"
        G
      end

      it "works" do
        bundle "config set --local path vendor"
        bundle "install"
        expect(the_bundle).to include_gems "myrack 1.0"
      end

      it "allows running bundle install --system without deleting foo" do
        bundle "install --path vendor"
        bundle "install --system"
        FileUtils.rm_r(bundled_app("vendor"))
        expect(the_bundle).to include_gems "myrack 1.0"
      end

      it "allows running bundle install --system after deleting foo" do
        bundle "install --path vendor"
        FileUtils.rm_r(bundled_app("vendor"))
        bundle "install --system"
        expect(the_bundle).to include_gems "myrack 1.0"
      end
    end

    it "finds gems in multiple sources" do
      build_repo2 do
        build_gem "myrack", "1.2" do |s|
          s.executables = "myrackup"
        end
      end

      install_gemfile <<-G, artifice: "compact_index_extra"
        source "https://gemserver.test"
        source "https://gemserver.test/extra"

        gem "activesupport", "1.2.3"
        gem "myrack", "1.2"
      G

      expect(the_bundle).to include_gems "myrack 1.2", "activesupport 1.2.3"
    end

    it "gives useful errors if no global sources are set, and gems not installed locally, with and without a lockfile" do
      install_gemfile <<-G, raise_on_error: false
        gem "myrack"
      G

      expect(err).to eq("Could not find gem 'myrack' in locally installed gems.")

      lockfile <<~L
        GEM
          specs:
            myrack (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          myrack

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "install", raise_on_error: false

      expect(err).to include(
        "Because your Gemfile specifies no global remote source, your bundle is locked to " \
        "myrack (1.0.0) from locally installed gems. However, myrack (1.0.0) is not installed. " \
        "You'll need to either add a global remote source to your Gemfile or make sure myrack (1.0.0) " \
        "is available locally before rerunning Bundler."
      )
    end

    it "creates a Gemfile.lock on a blank Gemfile" do
      install_gemfile <<-G
        source "https://gem.repo1"
      G

      expect(File.exist?(bundled_app_lock)).to eq(true)
    end

    it "throws a warning if a gem is added twice in Gemfile without version requirements" do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"
        gem "myrack"
      G

      expect(err).to include("Your Gemfile lists the gem myrack (>= 0) more than once.")
      expect(err).to include("Remove any duplicate entries and specify the gem only once.")
      expect(err).to include("While it's not a problem now, it could cause errors if you change the version of one of them later.")
    end

    it "throws a warning if a gem is added twice in Gemfile with same versions" do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack", "1.0"
        gem "myrack", "1.0"
      G

      expect(err).to include("Your Gemfile lists the gem myrack (= 1.0) more than once.")
      expect(err).to include("Remove any duplicate entries and specify the gem only once.")
      expect(err).to include("While it's not a problem now, it could cause errors if you change the version of one of them later.")
    end

    it "throws a warning if a gem is added twice under different platforms and does not crash when using the generated lockfile" do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack", :platform => :jruby
        gem "myrack"
      G

      bundle "install"

      expect(err).to include("Your Gemfile lists the gem myrack (>= 0) more than once.")
      expect(err).to include("Remove any duplicate entries and specify the gem only once.")
      expect(err).to include("While it's not a problem now, it could cause errors if you change the version of one of them later.")
    end

    it "does not throw a warning if a gem is added once in Gemfile and also inside a gemspec as a development dependency" do
      build_lib "my-gem", path: bundled_app do |s|
        s.add_development_dependency "my-private-gem"
      end

      build_repo2 do
        build_gem "my-private-gem"
      end

      gemfile <<~G
        source "https://gem.repo2"

        gemspec

        gem "my-private-gem", :group => :development
      G

      bundle :install

      expect(err).to be_empty
      expect(the_bundle).to include_gems("my-private-gem 1.0")
    end

    it "does not warn if a gem is added once in Gemfile and also inside a gemspec as a development dependency, with compatible requirements" do
      build_lib "my-gem", path: bundled_app do |s|
        s.add_development_dependency "rubocop", "~> 1.36.0"
      end

      build_repo4 do
        build_gem "rubocop", "1.36.0"
        build_gem "rubocop", "1.37.1"
      end

      gemfile <<~G
        source "https://gem.repo4"

        gemspec

        gem "rubocop", group: :development
      G

      bundle :install

      expect(err).to be_empty

      expect(the_bundle).to include_gems("rubocop 1.36.0")
    end

    it "raises an error if a gem is added once in Gemfile and also inside a gemspec as a development dependency, with incompatible requirements" do
      build_lib "my-gem", path: bundled_app do |s|
        s.add_development_dependency "rubocop", "~> 1.36.0"
      end

      build_repo4 do
        build_gem "rubocop", "1.36.0"
        build_gem "rubocop", "1.37.1"
      end

      gemfile <<~G
        source "https://gem.repo4"

        gemspec

        gem "rubocop", "~> 1.37.0", group: :development
      G

      bundle :install, raise_on_error: false

      expect(err).to include("The rubocop dependency has conflicting requirements in Gemfile (~> 1.37.0) and gemspec (~> 1.36.0)")
    end

    it "includes the gem without warning if two gemspecs add it with the same requirement" do
      gem1 = tmp("my-gem-1")
      gem2 = tmp("my-gem-2")

      build_lib "my-gem", path: gem1 do |s|
        s.add_development_dependency "rubocop", "~> 1.36.0"
      end

      build_lib "my-gem-2", path: gem2 do |s|
        s.add_development_dependency "rubocop", "~> 1.36.0"
      end

      build_repo4 do
        build_gem "rubocop", "1.36.0"
      end

      gemfile <<~G
        source "https://gem.repo4"

        gemspec path: "#{gem1}"
        gemspec path: "#{gem2}"
      G

      bundle :install

      expect(err).to be_empty
      expect(the_bundle).to include_gems("rubocop 1.36.0")
    end

    it "includes the gem without warning if two gemspecs add it with compatible requirements" do
      gem1 = tmp("my-gem-1")
      gem2 = tmp("my-gem-2")

      build_lib "my-gem", path: gem1 do |s|
        s.add_development_dependency "rubocop", "~> 1.0"
      end

      build_lib "my-gem-2", path: gem2 do |s|
        s.add_development_dependency "rubocop", "~> 1.36.0"
      end

      build_repo4 do
        build_gem "rubocop", "1.36.0"
      end

      gemfile <<~G
        source "https://gem.repo4"

        gemspec path: "#{gem1}"
        gemspec path: "#{gem2}"
      G

      bundle :install

      expect(err).to be_empty
      expect(the_bundle).to include_gems("rubocop 1.36.0")
    end

    it "errors out if two gemspecs add it with incompatible requirements" do
      gem1 = tmp("my-gem-1")
      gem2 = tmp("my-gem-2")

      build_lib "my-gem", path: gem1 do |s|
        s.add_development_dependency "rubocop", "~> 2.0"
      end

      build_lib "my-gem-2", path: gem2 do |s|
        s.add_development_dependency "rubocop", "~> 1.36.0"
      end

      build_repo4 do
        build_gem "rubocop", "1.36.0"
      end

      gemfile <<~G
        source "https://gem.repo4"

        gemspec path: "#{gem1}"
        gemspec path: "#{gem2}"
      G

      bundle :install, raise_on_error: false

      expect(err).to include("Two gemspec development dependencies have conflicting requirements on the same gem: rubocop (~> 1.36.0) and rubocop (~> 2.0). Bundler cannot continue.")
    end

    it "does not warn if a gem is added once in Gemfile and also inside a gemspec as a development dependency, with same requirements, and different sources" do
      build_lib "my-gem", path: bundled_app do |s|
        s.add_development_dependency "activesupport"
      end

      build_repo4 do
        build_gem "activesupport"
      end

      build_git "activesupport", "1.0", path: lib_path("activesupport")

      install_gemfile <<~G
        source "https://gem.repo4"

        gemspec

        gem "activesupport", :git => "#{lib_path("activesupport")}"
      G

      expect(err).to be_empty
      expect(the_bundle).to include_gems "activesupport 1.0", source: "git@#{lib_path("activesupport")}"

      # if the Gemfile dependency is specified first
      install_gemfile <<~G
        source "https://gem.repo4"

        gem "activesupport", :git => "#{lib_path("activesupport")}"

        gemspec
      G

      expect(err).to be_empty
      expect(the_bundle).to include_gems "activesupport 1.0", source: "git@#{lib_path("activesupport")}"
    end

    it "considers both dependencies for resolution if a gem is added once in Gemfile and also inside a local gemspec as a runtime dependency, with different requirements" do
      build_lib "my-gem", path: bundled_app do |s|
        s.add_dependency "rubocop", "~> 1.36.0"
      end

      build_repo4 do
        build_gem "rubocop", "1.36.0"
        build_gem "rubocop", "1.37.1"
      end

      gemfile <<~G
        source "https://gem.repo4"

        gemspec

        gem "rubocop"
      G

      bundle :install

      expect(err).to be_empty
      expect(the_bundle).to include_gems("rubocop 1.36.0")
    end

    it "throws an error if a gem is added twice in Gemfile when version of one dependency is not specified" do
      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo2"
        gem "myrack"
        gem "myrack", "1.0"
      G

      expect(err).to include("You cannot specify the same gem twice with different version requirements")
      expect(err).to include("You specified: myrack (>= 0) and myrack (= 1.0).")
    end

    it "throws an error if a gem is added twice in Gemfile when different versions of both dependencies are specified" do
      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo2"
        gem "myrack", "1.0"
        gem "myrack", "1.1"
      G

      expect(err).to include("You cannot specify the same gem twice with different version requirements")
      expect(err).to include("You specified: myrack (= 1.0) and myrack (= 1.1).")
    end

    it "gracefully handles error when rubygems server is unavailable" do
      install_gemfile <<-G, artifice: nil, raise_on_error: false
        source "https://gem.repo1"
        source "http://0.0.0.0:9384" do
          gem 'foo'
        end
      G

      expect(err).to eq("Could not reach host 0.0.0.0:9384. Check your network connection and try again.")
      expect(err).not_to include("file://")
    end

    it "fails gracefully when downloading an invalid specification from the full index" do
      build_repo2(build_compact_index: false) do
        build_gem "ajp-rails", "0.0.0", gemspec: false, skip_validation: true do |s|
          bad_deps = [["ruby-ajp", ">= 0.2.0"], ["rails", ">= 0.14"]]
          s.
            instance_variable_get(:@spec).
            instance_variable_set(:@dependencies, bad_deps)

          raise "failed to set bad deps" unless s.dependencies == bad_deps
        end
        build_gem "ruby-ajp", "1.0.0"
      end

      install_gemfile <<-G, full_index: true, raise_on_error: false
        source "https://gem.repo2"

        gem "ajp-rails", "0.0.0"
      G

      expect(stdboth).not_to match(/Error Report/i)
      expect(err).to include("An error occurred while installing ajp-rails (0.0.0), and Bundler cannot continue.").
        and include("Bundler::APIResponseInvalidDependenciesError")
    end

    it "doesn't blow up when the local .bundle/config is empty" do
      FileUtils.mkdir_p(bundled_app(".bundle"))
      FileUtils.touch(bundled_app(".bundle/config"))

      install_gemfile(<<-G)
        source "https://gem.repo1"

        gem 'foo'
      G
    end

    it "doesn't blow up when the global .bundle/config is empty" do
      FileUtils.mkdir_p("#{Bundler.rubygems.user_home}/.bundle")
      FileUtils.touch("#{Bundler.rubygems.user_home}/.bundle/config")

      install_gemfile(<<-G)
        source "https://gem.repo1"

        gem 'foo'
      G
    end
  end

  describe "Ruby version in Gemfile.lock" do
    context "and using an unsupported Ruby version" do
      it "prints an error" do
        install_gemfile <<-G, raise_on_error: false
          ruby '~> 1.2'
          source "https://gem.repo1"
        G
        expect(err).to include("Your Ruby version is #{Gem.ruby_version}, but your Gemfile specified ~> 1.2")
      end
    end

    context "and using a supported Ruby version" do
      before do
        install_gemfile <<-G
          ruby '~> #{Gem.ruby_version}'
          source "https://gem.repo1"
        G
      end

      it "writes current Ruby version to Gemfile.lock" do
        checksums = checksums_section_when_enabled
        expect(lockfile).to eq <<~L
         GEM
           remote: https://gem.repo1/
           specs:

         PLATFORMS
           #{lockfile_platforms}

         DEPENDENCIES
         #{checksums}
         RUBY VERSION
            #{Bundler::RubyVersion.system}

         BUNDLED WITH
            #{Bundler::VERSION}
        L
      end

      it "updates Gemfile.lock with updated yet still compatible ruby version" do
        install_gemfile <<-G
          ruby '~> #{current_ruby_minor}'
          source "https://gem.repo1"
        G

        checksums = checksums_section_when_enabled

        expect(lockfile).to eq <<~L
         GEM
           remote: https://gem.repo1/
           specs:

         PLATFORMS
           #{lockfile_platforms}

         DEPENDENCIES
         #{checksums}
         RUBY VERSION
            #{Bundler::RubyVersion.system}

         BUNDLED WITH
            #{Bundler::VERSION}
        L
      end

      it "does not crash when unlocking" do
        gemfile <<-G
          source "https://gem.repo1"
          ruby '>= 2.1.0'
        G

        bundle "update"

        expect(err).not_to include("Could not find gem 'Ruby")
      end
    end
  end

  describe "when Bundler root contains regex chars" do
    it "doesn't blow up when using the `gem` DSL" do
      root_dir = tmp("foo[]bar")

      FileUtils.mkdir_p(root_dir)

      build_lib "foo"
      gemfile = <<-G
        source "https://gem.repo1"
        gem 'foo', :path => "#{lib_path("foo-1.0")}"
      G
      File.open("#{root_dir}/Gemfile", "w") do |file|
        file.puts gemfile
      end

      bundle :install, dir: root_dir
    end

    it "doesn't blow up when using the `gemspec` DSL" do
      root_dir = tmp("foo[]bar")

      FileUtils.mkdir_p(root_dir)

      build_lib "foo", path: root_dir
      gemfile = <<-G
        source "https://gem.repo1"
        gemspec
      G
      File.open("#{root_dir}/Gemfile", "w") do |file|
        file.puts gemfile
      end

      bundle :install, dir: root_dir
    end
  end

  describe "when requesting a quiet install via --quiet" do
    it "should be quiet if there are no warnings" do
      bundle "config set force_ruby_platform true"

      gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G

      bundle :install, quiet: true
      expect(out).to be_empty
      expect(err).to be_empty
    end

    it "should still display warnings and errors" do
      bundle "config set force_ruby_platform true"

      create_file("install_with_warning.rb", <<~RUBY)
        require "#{lib_dir}/bundler"
        require "#{lib_dir}/bundler/cli"
        require "#{lib_dir}/bundler/cli/install"

        module RunWithWarning
          def run
            super
          rescue
            Bundler.ui.warn "BOOOOO"
            raise
          end
        end

        Bundler::CLI::Install.prepend(RunWithWarning)
      RUBY

      gemfile <<-G
        source "https://gem.repo1"
        gem 'non-existing-gem'
      G

      bundle :install, quiet: true, raise_on_error: false, env: { "RUBYOPT" => "-r#{bundled_app("install_with_warning.rb")}" }
      expect(out).to be_empty
      expect(err).to include("Could not find gem 'non-existing-gem'")
      expect(err).to include("BOOOOO")
    end
  end

  describe "when bundle path does not have cd permission", :permissions do
    let(:bundle_path) { bundled_app("vendor") }

    before do
      FileUtils.mkdir_p(bundle_path)
      gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G
    end

    it "should display a proper message to explain the problem" do
      FileUtils.chmod(0o500, bundle_path)

      bundle "config set --local path vendor"
      bundle :install, raise_on_error: false
      expect(err).to include(bundle_path.to_s)
      expect(err).to include("grant executable permissions")
    end
  end

  describe "when bundle gems path does not have cd permission", :permissions do
    let(:gems_path) { bundled_app("vendor/#{Bundler.ruby_scope}/gems") }

    before do
      FileUtils.mkdir_p(gems_path)
      gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G
    end

    it "should display a proper message to explain the problem" do
      FileUtils.chmod("-x", gems_path)
      bundle "config set --local path vendor"

      begin
        bundle :install, raise_on_error: false
      ensure
        FileUtils.chmod("+x", gems_path)
      end

      expect(err).not_to include("ERROR REPORT TEMPLATE")

      expect(err).to include(
        "There was an error while trying to create `#{gems_path.join("myrack-1.0.0")}`. " \
        "It is likely that you need to grant executable permissions for all parent directories and write permissions for `#{gems_path}`."
      )
    end
  end

  describe "when there's an empty install folder (like with default gems) without cd permissions", :permissions do
    let(:full_gem_path) { bundled_app("vendor/#{Bundler.ruby_scope}/gems/myrack-1.0.0") }

    before do
      FileUtils.mkdir_p(full_gem_path)
      gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G
    end

    it "should display a proper message to explain the problem" do
      FileUtils.chmod("-x", full_gem_path)
      bundle "config set --local path vendor"

      begin
        bundle :install, raise_on_error: false
      ensure
        FileUtils.chmod("+x", full_gem_path)
      end

      expect(err).not_to include("ERROR REPORT TEMPLATE")

      expect(err).to include(
        "There was an error while trying to write to `#{full_gem_path}`. " \
        "It is likely that you need to grant write permissions for that path."
      )
    end
  end

  describe "when bundle bin dir does not have cd permission", :permissions do
    let(:bin_dir) { bundled_app("vendor/#{Bundler.ruby_scope}/bin") }

    before do
      FileUtils.mkdir_p(bin_dir)
      gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G
    end

    it "should display a proper message to explain the problem" do
      FileUtils.chmod("-x", bin_dir)
      bundle "config set --local path vendor"

      begin
        bundle :install, raise_on_error: false
      ensure
        FileUtils.chmod("+x", bin_dir)
      end

      expect(err).not_to include("ERROR REPORT TEMPLATE")

      expect(err).to include(
        "There was an error while trying to write to `#{bin_dir}`. " \
        "It is likely that you need to grant write permissions for that path."
      )
    end
  end

  describe "when bundle bin dir does not have write access", :permissions do
    let(:bin_dir) { bundled_app("vendor/#{Bundler.ruby_scope}/bin") }

    before do
      FileUtils.mkdir_p(bin_dir)
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
    end

    it "should display a proper message to explain the problem" do
      FileUtils.chmod("-w", bin_dir)
      bundle "config set --local path vendor"

      begin
        bundle :install, raise_on_error: false
      ensure
        FileUtils.chmod("+w", bin_dir)
      end

      expect(err).not_to include("ERROR REPORT TEMPLATE")

      expect(err).to include(
        "There was an error while trying to write to `#{bin_dir}`. " \
        "It is likely that you need to grant write permissions for that path."
      )
    end
  end

  describe "when bundle extensions path does not have write access", :permissions do
    let(:extensions_path) { bundled_app("vendor/#{Bundler.ruby_scope}/extensions/#{Gem::Platform.local}/#{Gem.extension_api_version}") }

    before do
      FileUtils.mkdir_p(extensions_path)
      gemfile <<-G
        source "https://gem.repo1"
        gem 'simple_binary'
      G
    end

    it "should display a proper message to explain the problem" do
      FileUtils.chmod("-x", extensions_path)
      bundle "config set --local path vendor"

      begin
        bundle :install, raise_on_error: false
      ensure
        FileUtils.chmod("+x", extensions_path)
      end

      expect(err).not_to include("ERROR REPORT TEMPLATE")

      expect(err).to include(
        "There was an error while trying to create `#{extensions_path.join("simple_binary-1.0")}`. " \
        "It is likely that you need to grant executable permissions for all parent directories and write permissions for `#{extensions_path}`."
      )
    end
  end

  describe "when the path of a specific gem does not have cd permission", :permissions do
    let(:gems_path) { bundled_app("vendor/#{Bundler.ruby_scope}/gems") }
    let(:foo_path) { gems_path.join("foo-1.0.0") }

    before do
      build_repo4 do
        build_gem "foo", "1.0.0" do |s|
          s.write "CHANGELOG.md", "foo"
        end
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem 'foo'
      G
    end

    it "should display a proper message to explain the problem" do
      bundle "config set --local path vendor"
      bundle :install
      expect(out).to include("Bundle complete!")
      expect(err).to be_empty

      FileUtils.chmod("-x", foo_path)

      begin
        bundle "install --force", raise_on_error: false
      ensure
        FileUtils.chmod("+x", foo_path)
      end

      expect(err).not_to include("ERROR REPORT TEMPLATE")
      expect(err).to include("Could not delete previous installation of `#{foo_path}`.")
      expect(err).to include("The underlying error was Errno::EACCES")
    end
  end

  describe "when gem home does not have the writable bit set, yet it's still writable", :permissions do
    let(:gem_home) { bundled_app("vendor/#{Bundler.ruby_scope}") }

    before do
      build_repo4 do
        build_gem "foo", "1.0.0" do |s|
          s.write "CHANGELOG.md", "foo"
        end
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem 'foo'
      G
    end

    it "should still work" do
      bundle "config set --local path vendor"
      bundle :install
      expect(out).to include("Bundle complete!")
      expect(err).to be_empty

      FileUtils.chmod("-w", gem_home)

      begin
        bundle "install --force"
      ensure
        FileUtils.chmod("+w", gem_home)
      end

      expect(out).to include("Bundle complete!")
      expect(err).to be_empty
    end
  end

  describe "when gems path is world writable (no sticky bit set)", :permissions do
    let(:gems_path) { bundled_app("vendor/#{Bundler.ruby_scope}/gems") }

    before do
      build_repo4 do
        build_gem "foo", "1.0.0" do |s|
          s.write "CHANGELOG.md", "foo"
        end
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem 'foo'
      G
    end

    it "should display a proper message to explain the problem" do
      bundle "config set --local path vendor"
      bundle :install
      expect(out).to include("Bundle complete!")
      expect(err).to be_empty

      FileUtils.chmod(0o777, gems_path)

      bundle "install --force", raise_on_error: false

      expect(err).to include("Bundler cannot reinstall foo-1.0.0 because there's a previous installation of it at #{gems_path}/foo-1.0.0 that is unsafe to remove")
    end
  end

  describe "when gems path is world writable (no sticky bit set), but previous install is just an empty dir (like it happens with default gems)", :permissions do
    let(:gems_path) { bundled_app("vendor/#{Bundler.ruby_scope}/gems") }
    let(:full_path) { gems_path.join("foo-1.0.0") }

    before do
      build_repo4 do
        build_gem "foo", "1.0.0" do |s|
          s.write "CHANGELOG.md", "foo"
        end
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem 'foo'
      G
    end

    it "does not try to remove the directory and thus don't abort with an error about unsafe directory removal" do
      bundle "config set --local path vendor"

      FileUtils.mkdir_p(gems_path)
      FileUtils.chmod(0o777, gems_path)
      Dir.mkdir(full_path)

      bundle "install"
    end
  end

  describe "when bundle cache path does not have write access", :permissions do
    let(:cache_path) { bundled_app("vendor/#{Bundler.ruby_scope}/cache") }

    before do
      FileUtils.mkdir_p(cache_path)
      gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G
    end

    it "should display a proper message to explain the problem" do
      FileUtils.chmod(0o500, cache_path)

      bundle "config set --local path vendor"
      bundle :install, raise_on_error: false
      expect(err).to include(cache_path.to_s)
      expect(err).to include("grant write permissions")
    end
  end

  describe "when gemspecs are unreadable", :permissions do
    let(:gemspec_path) { vendored_gems("specifications/myrack-1.0.0.gemspec") }

    before do
      gemfile <<~G
        source "https://gem.repo1"
        gem 'myrack'
      G
      bundle "config path vendor/bundle"
      bundle :install
      expect(out).to include("Bundle complete!")
      expect(err).to be_empty

      FileUtils.chmod("-r", gemspec_path)
    end

    it "shows a good error" do
      bundle :install, raise_on_error: false
      expect(err).to include(gemspec_path.to_s)
      expect(err).to include("grant read permissions")
    end
  end

  describe "when configured path is UTF-8 and a file inside a gem package too" do
    let(:app_path) do
      path = tmp("♥")
      FileUtils.mkdir_p(path)
      path
    end

    let(:path) do
      root.join("vendor/bundle")
    end

    before do
      build_repo4 do
        build_gem "mygem" do |s|
          s.write "spec/fixtures/_posts/2016-04-01-错误.html"
        end
      end
    end

    it "works" do
      bundle "config path #{app_path}/vendor/bundle", dir: app_path

      install_gemfile app_path.join("Gemfile"),<<~G, dir: app_path
        source "https://gem.repo4"
        gem "mygem", "1.0"
      G
    end
  end

  context "after installing with --standalone" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
      bundle "config set --local path bundle"
      bundle "install", standalone: true
    end

    it "includes the standalone path" do
      bundle "binstubs myrack", standalone: true
      standalone_line = File.read(bundled_app("bin/myrackup")).each_line.find {|line| line.include? "$:.unshift" }.strip
      expect(standalone_line).to eq %($:.unshift File.expand_path "../bundle", __dir__)
    end
  end

  describe "when bundle install is executed with unencoded authentication" do
    before do
      gemfile <<-G
        source 'https://rubygems.org/'
        gem "."
      G
    end

    it "should display a helpful message explaining how to fix it" do
      bundle :install, env: { "BUNDLE_RUBYGEMS__ORG" => "user:pass{word" }, raise_on_error: false
      expect(exitstatus).to eq(17)
      expect(err).to eq("Please CGI escape your usernames and passwords before " \
                        "setting them for authentication.")
    end
  end

  context "when current platform not included in the lockfile" do
    around do |example|
      build_repo4 do
        build_gem "libv8", "8.4.255.0" do |s|
          s.platform = "x86_64-darwin-19"
        end

        build_gem "libv8", "8.4.255.0" do |s|
          s.platform = "x86_64-linux"
        end
      end

      gemfile <<-G
        source "https://gem.repo4"

        gem "libv8"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo4/
          specs:
            libv8 (8.4.255.0-x86_64-darwin-19)

        PLATFORMS
          x86_64-darwin-19

        DEPENDENCIES
          libv8

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      simulate_platform("x86_64-linux", &example)
    end

    it "adds the current platform to the lockfile" do
      bundle "install --verbose"

      expect(out).to include("re-resolving dependencies because your lockfile is missing the current platform")
      expect(out).not_to include("you are adding a new platform to your lockfile")

      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            libv8 (8.4.255.0-x86_64-darwin-19)
            libv8 (8.4.255.0-x86_64-linux)

        PLATFORMS
          x86_64-darwin-19
          x86_64-linux

        DEPENDENCIES
          libv8

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end

    it "fails loudly if frozen mode set" do
      bundle "config set --local deployment true"
      bundle "install", raise_on_error: false

      expect(err).to eq(
        "Your bundle only supports platforms [\"x86_64-darwin-19\"] but your local platform is x86_64-linux. " \
        "Add the current platform to the lockfile with\n`bundle lock --add-platform x86_64-linux` and try again."
      )
    end
  end

  context "with missing platform specific gems in lockfile" do
    before do
      build_repo4 do
        build_gem "racca", "1.5.2"

        build_gem "nokogiri", "1.12.4" do |s|
          s.platform = "x86_64-darwin"
          s.add_dependency "racca", "~> 1.4"
        end

        build_gem "nokogiri", "1.12.4" do |s|
          s.platform = "x86_64-linux"
          s.add_dependency "racca", "~> 1.4"
        end

        build_gem "crass", "1.0.6"

        build_gem "loofah", "2.12.0" do |s|
          s.add_dependency "crass", "~> 1.0.2"
          s.add_dependency "nokogiri", ">= 1.5.9"
        end
      end

      gemfile <<-G
        source "https://gem.repo4"

        ruby "#{Gem.ruby_version}"

        gem "loofah", "~> 2.12.0"
      G

      checksums = checksums_section do |c|
        c.checksum gem_repo4, "crass", "1.0.6"
        c.checksum gem_repo4, "loofah", "2.12.0"
        c.checksum gem_repo4, "nokogiri", "1.12.4", "x86_64-darwin"
        c.checksum gem_repo4, "racca", "1.5.2"
      end

      lockfile <<-L
        GEM
          remote: https://gem.repo4/
          specs:
            crass (1.0.6)
            loofah (2.12.0)
              crass (~> 1.0.2)
              nokogiri (>= 1.5.9)
            nokogiri (1.12.4-x86_64-darwin)
              racca (~> 1.4)
            racca (1.5.2)

        PLATFORMS
          x86_64-darwin-20
          x86_64-linux

        DEPENDENCIES
          loofah (~> 2.12.0)
        #{checksums}
        RUBY VERSION
           #{Bundler::RubyVersion.system}

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end

    it "automatically fixes the lockfile" do
      bundle "config set --local path vendor/bundle"

      simulate_platform "x86_64-linux" do
        bundle "install", artifice: "compact_index"
      end

      checksums = checksums_section_when_enabled do |c|
        c.checksum gem_repo4, "crass", "1.0.6"
        c.checksum gem_repo4, "loofah", "2.12.0"
        c.checksum gem_repo4, "nokogiri", "1.12.4", "x86_64-darwin"
        c.checksum gem_repo4, "racca", "1.5.2"
        c.checksum gem_repo4, "nokogiri", "1.12.4", "x86_64-linux"
      end

      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            crass (1.0.6)
            loofah (2.12.0)
              crass (~> 1.0.2)
              nokogiri (>= 1.5.9)
            nokogiri (1.12.4-x86_64-darwin)
              racca (~> 1.4)
            nokogiri (1.12.4-x86_64-linux)
              racca (~> 1.4)
            racca (1.5.2)

        PLATFORMS
          x86_64-darwin-20
          x86_64-linux

        DEPENDENCIES
          loofah (~> 2.12.0)
        #{checksums}
        RUBY VERSION
           #{Bundler::RubyVersion.system}

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end
  end

  context "when lockfile has incorrect dependencies" do
    before do
      build_repo2

      gemfile <<-G
        source "https://gem.repo2"
        gem "myrack_middleware"
      G

      system_gems "myrack_middleware-1.0", path: default_bundle_path

      # we want to raise when the 1.0 line should be followed by "            myrack (= 0.9.1)" but isn't
      lockfile <<-L
        GEM
          remote: https://gem.repo2/
          specs:
            myrack_middleware (1.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          myrack_middleware

        BUNDLED WITH
          #{Bundler::VERSION}
      L
    end

    it "raises a clear error message when frozen" do
      bundle "config set frozen true"
      bundle "install", raise_on_error: false

      expect(exitstatus).to eq(41)
      expect(err).to eq("Bundler found incorrect dependencies in the lockfile for myrack_middleware-1.0")
    end

    it "updates the lockfile when not frozen" do
      missing_dep = "myrack (0.9.1)"
      expect(lockfile).not_to include(missing_dep)

      bundle "config set frozen false"
      bundle :install

      expect(lockfile).to include(missing_dep)
      expect(out).to include("now installed")
    end
  end

  context "with --local flag" do
    before do
      system_gems "myrack-1.0.0", path: default_bundle_path
    end

    it "respects installed gems without fetching any remote sources" do
      install_gemfile <<-G, local: true
        source "https://gem.repo1"

        source "https://not-existing-source" do
          gem "myrack"
        end
      G

      expect(last_command).to be_success
    end
  end

  context "with only option" do
    before do
      bundle "config set only a:b"
    end

    it "installs only gems of the specified groups" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rails"
        gem "myrack", group: :a
        gem "rake", group: :b
        gem "yard", group: :c
      G

      expect(out).to include("Installing myrack")
      expect(out).to include("Installing rake")
      expect(out).not_to include("Installing yard")
    end
  end

  context "with --prefer-local flag" do
    context "and gems available locally" do
      before do
        build_repo4 do
          build_gem "foo", "1.0.1"
          build_gem "foo", "1.0.0"
          build_gem "bar", "1.0.0"

          build_gem "a", "1.0.0" do |s|
            s.add_dependency "foo", "~> 1.0.0"
          end

          build_gem "b", "1.0.0" do |s|
            s.add_dependency "foo", "~> 1.0.1"
          end
        end

        system_gems "foo-1.0.0", path: default_bundle_path, gem_repo: gem_repo4
      end

      it "fetches remote sources when not available locally" do
        install_gemfile <<-G, "prefer-local": true, verbose: true
          source "https://gem.repo4"

          gem "foo"
          gem "bar"
        G

        expect(out).to include("Using foo 1.0.0").and include("Fetching bar 1.0.0").and include("Installing bar 1.0.0")
        expect(last_command).to be_success
      end

      it "fetches remote sources when local version does not match requirements" do
        install_gemfile <<-G, "prefer-local": true, verbose: true
          source "https://gem.repo4"

          gem "foo", "1.0.1"
          gem "bar"
        G

        expect(out).to include("Fetching foo 1.0.1").and include("Installing foo 1.0.1").and include("Fetching bar 1.0.0").and include("Installing bar 1.0.0")
        expect(last_command).to be_success
      end

      it "uses the locally available version for sub-dependencies when possible" do
        install_gemfile <<-G, "prefer-local": true, verbose: true
          source "https://gem.repo4"

          gem "a"
        G

        expect(out).to include("Using foo 1.0.0").and include("Fetching a 1.0.0").and include("Installing a 1.0.0")
        expect(last_command).to be_success
      end

      it "fetches remote sources for sub-dependencies when the locally available version does not satisfy the requirement" do
        install_gemfile <<-G, "prefer-local": true, verbose: true
          source "https://gem.repo4"

          gem "b"
        G

        expect(out).to include("Fetching foo 1.0.1").and include("Installing foo 1.0.1").and include("Fetching b 1.0.0").and include("Installing b 1.0.0")
        expect(last_command).to be_success
      end
    end

    context "and no gems available locally" do
      before do
        build_repo4 do
          build_gem "myreline", "0.3.8"
          build_gem "debug", "0.2.1"

          build_gem "debug", "1.10.0" do |s|
            s.add_dependency "myreline"
          end
        end
      end

      it "resolves to the latest version if no gems are available locally" do
        install_gemfile <<~G, "prefer-local": true, verbose: true
          source "https://gem.repo4"

          gem "debug"
        G

        expect(out).to include("Fetching debug 1.10.0").and include("Installing debug 1.10.0").and include("Fetching myreline 0.3.8").and include("Installing myreline 0.3.8")
        expect(last_command).to be_success
      end
    end
  end

  context "with a symlinked configured as bundle path and a gem with symlinks" do
    before do
      symlinked_bundled_app = tmp("bundled_app-symlink")
      File.symlink(bundled_app, symlinked_bundled_app)
      bundle "config path #{File.join(symlinked_bundled_app, ".vendor")}"

      binman_path = tmp("binman")
      FileUtils.mkdir_p binman_path

      readme_path = File.join(binman_path, "README.markdown")
      FileUtils.touch(readme_path)

      man_path = File.join(binman_path, "man", "man0")
      FileUtils.mkdir_p man_path

      File.symlink("../../README.markdown", File.join(man_path, "README.markdown"))

      build_repo4 do
        build_gem "binman", path: gem_repo4("gems"), lib_path: binman_path, no_default: true do |s|
          s.files = ["README.markdown", "man/man0/README.markdown"]
        end
      end
    end

    it "installs fine" do
      install_gemfile <<~G
        source "https://gem.repo4"

        gem "binman"
      G
    end
  end

  context "when a gem has equivalent versions with inconsistent dependencies" do
    before do
      build_repo4 do
        build_gem "autobuild", "1.10.rc2" do |s|
          s.add_dependency "utilrb", ">= 1.6.0"
        end

        build_gem "autobuild", "1.10.0.rc2" do |s|
          s.add_dependency "utilrb", ">= 2.0"
        end
      end
    end

    it "does not crash unexpectedly" do
      gemfile <<~G
        source "https://gem.repo4"

        gem "autobuild", "1.10.rc2"
      G

      bundle "install --jobs 1", raise_on_error: false

      expect(err).not_to include("ERROR REPORT TEMPLATE")
      expect(err).to include("Could not find compatible versions")
    end
  end

  context "when a lockfile has unmet dependencies, and the Gemfile has no resolution" do
    before do
      build_repo4 do
        build_gem "aaa", "0.2.0" do |s|
          s.add_dependency "zzz", "< 0.2.0"
        end

        build_gem "zzz", "0.2.0"
      end

      gemfile <<~G
        source "https://gem.repo4"

        gem "aaa"
        gem "zzz"
      G

      lockfile <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            aaa (0.2.0)
              zzz (< 0.2.0)
            zzz (0.2.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          aaa!
          zzz!

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end

    it "does not install, but raises a resolution error" do
      bundle "install", raise_on_error: false
      expect(err).to include("Could not find compatible versions")
    end
  end

  context "when --jobs option given" do
    before do
      install_gemfile "source 'https://gem.repo1'", jobs: 1
    end

    it "does not save the flag to config" do
      expect(bundled_app(".bundle/config")).not_to exist
    end
  end

  context "when bundler installation is corrupt" do
    before do
      system_gems "bundler-9.99.8"

      replace_version_file("9.99.9", dir: system_gem_path("gems/bundler-9.99.8"))
    end

    it "shows a proper error" do
      lockfile <<~L
        GEM
          remote: https://gem.repo1/
          specs:

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES

        BUNDLED WITH
           9.99.8
      L

      install_gemfile "source \"https://gem.repo1\"", env: { "BUNDLER_VERSION" => "9.99.8" }, raise_on_error: false

      expect(err).not_to include("ERROR REPORT TEMPLATE")
      expect(err).to include("The running version of Bundler (9.99.9) does not match the version of the specification installed for it (9.99.8)")
    end
  end

  it "only installs executable files in bin" do
    bundle "config set --local path vendor/bundle"

    install_gemfile <<~G
      source "https://gem.repo1"
      gem "myrack"
    G

    expected_executables = [vendored_gems("bin/myrackup").to_s]
    expected_executables << vendored_gems("bin/myrackup.bat").to_s if Gem.win_platform?
    expect(Dir.glob(vendored_gems("bin/*"))).to eq(expected_executables)
  end

  it "preserves lockfile versions conservatively" do
    build_repo4 do
      build_gem "mypsych", "4.0.6" do |s|
        s.add_dependency "mystringio"
      end

      build_gem "mypsych", "5.1.2" do |s|
        s.add_dependency "mystringio"
      end

      build_gem "mystringio", "3.1.0"
      build_gem "mystringio", "3.1.1"
    end

    lockfile <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          mypsych (4.0.6)
            mystringio
          mystringio (3.1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        mypsych (~> 4.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    install_gemfile <<~G
      source "https://gem.repo4"
      gem "mypsych", "~> 5.0"
    G

    expect(lockfile).to eq <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          mypsych (5.1.2)
            mystringio
          mystringio (3.1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        mypsych (~> 5.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end
end
