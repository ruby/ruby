# frozen_string_literal: true

RSpec.describe "bundle install with gem sources" do
  describe "the simple case" do
    it "prints output and returns if no dependencies are specified" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
      G

      bundle :install
      expect(err).to match(/no dependencies/)
    end

    it "does not make a lockfile if the install fails" do
      install_gemfile <<-G, :raise_on_error => false
        raise StandardError, "FAIL"
      G

      expect(err).to include('StandardError, "FAIL"')
      expect(bundled_app_lock).not_to exist
    end

    it "creates a Gemfile.lock" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      expect(bundled_app_lock).to exist
    end

    it "does not create ./.bundle by default", :bundler => "< 3" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      bundle :install # can't use install_gemfile since it sets retry
      expect(bundled_app(".bundle")).not_to exist
    end

    it "does not create ./.bundle by default when installing to system gems" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      bundle :install, :env => { "BUNDLE_PATH__SYSTEM" => "true" } # can't use install_gemfile since it sets retry
      expect(bundled_app(".bundle")).not_to exist
    end

    it "creates lock files based on the Gemfile name" do
      gemfile bundled_app("OmgFile"), <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", "1.0"
      G

      bundle "install --gemfile OmgFile"

      expect(bundled_app("OmgFile.lock")).to exist
    end

    it "doesn't delete the lockfile if one already exists" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack'
      G

      lockfile = File.read(bundled_app_lock)

      install_gemfile <<-G, :raise_on_error => false
        raise StandardError, "FAIL"
      G

      expect(File.read(bundled_app_lock)).to eq(lockfile)
    end

    it "does not touch the lockfile if nothing changed" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      expect { run "1" }.not_to change { File.mtime(bundled_app_lock) }
    end

    it "fetches gems" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack'
      G

      expect(default_bundle_path("gems/rack-1.0.0")).to exist
      expect(the_bundle).to include_gems("rack 1.0.0")
    end

    it "auto-heals missing gems" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack'
      G

      FileUtils.rm_rf(default_bundle_path("gems/rack-1.0.0"))

      bundle "install --verbose"

      expect(out).to include("Installing rack 1.0.0")
      expect(default_bundle_path("gems/rack-1.0.0")).to exist
      expect(the_bundle).to include_gems("rack 1.0.0")
    end

    it "fetches gems when multiple versions are specified" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack', "> 0.9", "< 1.0"
      G

      expect(default_bundle_path("gems/rack-0.9.1")).to exist
      expect(the_bundle).to include_gems("rack 0.9.1")
    end

    it "fetches gems when multiple versions are specified take 2" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack', "< 1.0", "> 0.9"
      G

      expect(default_bundle_path("gems/rack-0.9.1")).to exist
      expect(the_bundle).to include_gems("rack 0.9.1")
    end

    it "raises an appropriate error when gems are specified using symbols" do
      install_gemfile <<-G, :raise_on_error => false
        source "#{file_uri_for(gem_repo1)}"
        gem :rack
      G
      expect(exitstatus).to eq(4)
    end

    it "pulls in dependencies" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails"
      G

      expect(the_bundle).to include_gems "actionpack 2.3.2", "rails 2.3.2"
    end

    it "does the right version" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", "0.9.1"
      G

      expect(the_bundle).to include_gems "rack 0.9.1"
    end

    it "does not install the development dependency" do
      build_repo2 do
        build_gem "with_development_dependency" do |s|
          s.add_development_dependency "activesupport", "= 2.3.5"
        end
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "with_development_dependency"
      G

      expect(the_bundle).to include_gems("with_development_dependency 1.0.0").
        and not_include_gems("activesupport 2.3.5")
    end

    it "resolves correctly" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "activemerchant"
        gem "rails"
      G

      expect(the_bundle).to include_gems "activemerchant 1.0", "activesupport 2.3.2", "actionpack 2.3.2"
    end

    it "activates gem correctly according to the resolved gems" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "activesupport", "2.3.5"
      G

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "activemerchant"
        gem "rails"
      G

      expect(the_bundle).to include_gems "activemerchant 1.0", "activesupport 2.3.2", "actionpack 2.3.2"
    end

    it "does not reinstall any gem that is already available locally" do
      system_gems "activesupport-2.3.2", :path => default_bundle_path

      build_repo2 do
        build_gem "activesupport", "2.3.2" do |s|
          s.write "lib/activesupport.rb", "ACTIVESUPPORT = 'fail'"
        end
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "activerecord", "2.3.2"
      G

      expect(the_bundle).to include_gems "activesupport 2.3.2"
    end

    it "works when the gemfile specifies gems that only exist in the system" do
      build_gem "foo", :to_bundle => true
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
        gem "foo"
      G

      expect(the_bundle).to include_gems "rack 1.0.0", "foo 1.0.0"
    end

    it "prioritizes local gems over remote gems" do
      build_gem "rack", "1.0.0", :to_bundle => true do |s|
        s.add_dependency "activesupport", "2.3.5"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      expect(the_bundle).to include_gems "rack 1.0.0", "activesupport 2.3.5"
    end

    it "loads env plugins" do
      plugin_msg = "hello from an env plugin!"
      create_file "plugins/rubygems_plugin.rb", "puts '#{plugin_msg}'"
      rubylib = ENV["RUBYLIB"].to_s.split(File::PATH_SEPARATOR).unshift(bundled_app("plugins").to_s).join(File::PATH_SEPARATOR)
      install_gemfile <<-G, :env => { "RUBYLIB" => rubylib }
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      expect(last_command.stdboth).to include(plugin_msg)
    end

    describe "with a gem that installs multiple platforms" do
      it "installs gems for the local platform as first choice" do
        skip "version is 1.0, not 1.0.0" if Gem.win_platform?

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "platform_specific"
        G

        run "require 'platform_specific' ; puts PLATFORM_SPECIFIC"
        expect(out).to eq("1.0.0 #{Bundler.local_platform}")
      end

      it "falls back on plain ruby" do
        simulate_platform "foo-bar-baz"
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "platform_specific"
        G

        run "require 'platform_specific' ; puts PLATFORM_SPECIFIC"
        expect(out).to eq("1.0.0 RUBY")
      end

      it "installs gems for java" do
        simulate_platform "java"
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "platform_specific"
        G

        run "require 'platform_specific' ; puts PLATFORM_SPECIFIC"
        expect(out).to eq("1.0.0 JAVA")
      end

      it "installs gems for windows" do
        simulate_platform mswin

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "platform_specific"
        G

        run "require 'platform_specific' ; puts PLATFORM_SPECIFIC"
        expect(out).to eq("1.0.0 MSWIN")
      end
    end

    describe "doing bundle install foo" do
      before do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rack"
        G
      end

      it "works" do
        bundle "config set --local path vendor"
        bundle "install"
        expect(the_bundle).to include_gems "rack 1.0"
      end

      it "allows running bundle install --system without deleting foo", :bundler => "< 3" do
        bundle "install --path vendor"
        bundle "install --system"
        FileUtils.rm_rf(bundled_app("vendor"))
        expect(the_bundle).to include_gems "rack 1.0"
      end

      it "allows running bundle install --system after deleting foo", :bundler => "< 3" do
        bundle "install --path vendor"
        FileUtils.rm_rf(bundled_app("vendor"))
        bundle "install --system"
        expect(the_bundle).to include_gems "rack 1.0"
      end
    end

    it "finds gems in multiple sources", :bundler => "< 3" do
      build_repo2 do
        build_gem "rack", "1.2" do |s|
          s.executables = "rackup"
        end
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        source "#{file_uri_for(gem_repo2)}"

        gem "activesupport", "1.2.3"
        gem "rack", "1.2"
      G

      expect(the_bundle).to include_gems "rack 1.2", "activesupport 1.2.3"
    end

    it "gives a useful error if no sources are set" do
      install_gemfile <<-G, :raise_on_error => false
        gem "rack"
      G

      expect(err).to include("This Gemfile does not include an explicit global source. " \
        "Not using an explicit global source may result in a different lockfile being generated depending on " \
        "the gems you have installed locally before bundler is run. " \
        "Instead, define a global source in your Gemfile like this: source \"https://rubygems.org\".")
    end

    it "creates a Gemfile.lock on a blank Gemfile" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
      G

      expect(File.exist?(bundled_app_lock)).to eq(true)
    end

    it "throws a warning if a gem is added twice in Gemfile without version requirements" do
      install_gemfile <<-G, :raise_on_error => false
        source "#{file_uri_for(gem_repo2)}"
        gem "rack"
        gem "rack"
      G

      expect(err).to include("Your Gemfile lists the gem rack (>= 0) more than once.")
      expect(err).to include("Remove any duplicate entries and specify the gem only once.")
      expect(err).to include("While it's not a problem now, it could cause errors if you change the version of one of them later.")
    end

    it "throws a warning if a gem is added twice in Gemfile with same versions" do
      install_gemfile <<-G, :raise_on_error => false
        source "#{file_uri_for(gem_repo2)}"
        gem "rack", "1.0"
        gem "rack", "1.0"
      G

      expect(err).to include("Your Gemfile lists the gem rack (= 1.0) more than once.")
      expect(err).to include("Remove any duplicate entries and specify the gem only once.")
      expect(err).to include("While it's not a problem now, it could cause errors if you change the version of one of them later.")
    end

    it "does not throw a warning if a gem is added once in Gemfile and also inside a gemspec as a development dependency" do
      build_lib "my-gem", :path => bundled_app do |s|
        s.add_development_dependency "my-private-gem"
      end

      build_repo2 do
        build_gem "my-private-gem"
      end

      gemfile <<~G
        source "#{file_uri_for(gem_repo2)}"

        gemspec

        gem "my-private-gem", :group => :development
      G

      bundle :install

      expect(err).to be_empty
      expect(the_bundle).to include_gems("my-private-gem 1.0")
    end

    it "throws an error if a gem is added twice in Gemfile when version of one dependency is not specified" do
      install_gemfile <<-G, :raise_on_error => false
        source "#{file_uri_for(gem_repo2)}"
        gem "rack"
        gem "rack", "1.0"
      G

      expect(err).to include("You cannot specify the same gem twice with different version requirements")
      expect(err).to include("You specified: rack (>= 0) and rack (= 1.0).")
    end

    it "throws an error if a gem is added twice in Gemfile when different versions of both dependencies are specified" do
      install_gemfile <<-G, :raise_on_error => false
        source "#{file_uri_for(gem_repo2)}"
        gem "rack", "1.0"
        gem "rack", "1.1"
      G

      expect(err).to include("You cannot specify the same gem twice with different version requirements")
      expect(err).to include("You specified: rack (= 1.0) and rack (= 1.1).")
    end

    it "gracefully handles error when rubygems server is unavailable" do
      skip "networking issue" if Gem.win_platform?

      install_gemfile <<-G, :artifice => nil, :raise_on_error => false
        source "#{file_uri_for(gem_repo1)}"
        source "http://0.0.0.0:9384" do
          gem 'foo'
        end
      G

      expect(err).to include("Could not fetch specs from http://0.0.0.0:9384/")
      expect(err).not_to include("file://")
    end

    it "fails gracefully when downloading an invalid specification from the full index" do
      build_repo2 do
        build_gem "ajp-rails", "0.0.0", :gemspec => false, :skip_validation => true do |s|
          bad_deps = [["ruby-ajp", ">= 0.2.0"], ["rails", ">= 0.14"]]
          s.
            instance_variable_get(:@spec).
            instance_variable_set(:@dependencies, bad_deps)

          raise "failed to set bad deps" unless s.dependencies == bad_deps
        end
        build_gem "ruby-ajp", "1.0.0"
      end

      install_gemfile <<-G, :full_index => true, :raise_on_error => false
        source "#{file_uri_for(gem_repo2)}"

        gem "ajp-rails", "0.0.0"
      G

      expect(last_command.stdboth).not_to match(/Error Report/i)
      expect(err).to include("An error occurred while installing ajp-rails (0.0.0), and Bundler cannot continue.").
        and include("Bundler::APIResponseInvalidDependenciesError")
    end

    it "doesn't blow up when the local .bundle/config is empty" do
      FileUtils.mkdir_p(bundled_app(".bundle"))
      FileUtils.touch(bundled_app(".bundle/config"))

      install_gemfile(<<-G)
        source "#{file_uri_for(gem_repo1)}"

        gem 'foo'
      G
    end

    it "doesn't blow up when the global .bundle/config is empty" do
      FileUtils.mkdir_p("#{Bundler.rubygems.user_home}/.bundle")
      FileUtils.touch("#{Bundler.rubygems.user_home}/.bundle/config")

      install_gemfile(<<-G)
        source "#{file_uri_for(gem_repo1)}"

        gem 'foo'
      G
    end
  end

  describe "Ruby version in Gemfile.lock" do
    include Bundler::GemHelpers

    context "and using an unsupported Ruby version" do
      it "prints an error" do
        install_gemfile <<-G, :raise_on_error => false
          ruby '~> 1.2'
          source "#{file_uri_for(gem_repo1)}"
        G
        expect(err).to include("Your Ruby version is #{RUBY_VERSION}, but your Gemfile specified ~> 1.2")
      end
    end

    context "and using a supported Ruby version" do
      before do
        install_gemfile <<-G
          ruby '~> #{RUBY_VERSION}'
          source "#{file_uri_for(gem_repo1)}"
        G
      end

      it "writes current Ruby version to Gemfile.lock" do
        expect(lockfile).to eq <<~L
         GEM
           remote: #{file_uri_for(gem_repo1)}/
           specs:

         PLATFORMS
           #{lockfile_platforms}

         DEPENDENCIES

         RUBY VERSION
            #{Bundler::RubyVersion.system}

         BUNDLED WITH
            #{Bundler::VERSION}
        L
      end

      it "updates Gemfile.lock with updated yet still compatible ruby version" do
        install_gemfile <<-G
          ruby '~> #{RUBY_VERSION[0..2]}'
          source "#{file_uri_for(gem_repo1)}"
        G

        expect(lockfile).to eq <<~L
         GEM
           remote: #{file_uri_for(gem_repo1)}/
           specs:

         PLATFORMS
           #{lockfile_platforms}

         DEPENDENCIES

         RUBY VERSION
            #{Bundler::RubyVersion.system}

         BUNDLED WITH
            #{Bundler::VERSION}
        L
      end

      it "does not crash when unlocking" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
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
        source "#{file_uri_for(gem_repo1)}"
        gem 'foo', :path => "#{lib_path("foo-1.0")}"
      G
      File.open("#{root_dir}/Gemfile", "w") do |file|
        file.puts gemfile
      end

      bundle :install, :dir => root_dir
    end

    it "doesn't blow up when using the `gemspec` DSL" do
      root_dir = tmp("foo[]bar")

      FileUtils.mkdir_p(root_dir)

      build_lib "foo", :path => root_dir
      gemfile = <<-G
        source "#{file_uri_for(gem_repo1)}"
        gemspec
      G
      File.open("#{root_dir}/Gemfile", "w") do |file|
        file.puts gemfile
      end

      bundle :install, :dir => root_dir
    end
  end

  describe "when requesting a quiet install via --quiet" do
    it "should be quiet if there are no warnings" do
      bundle "config set force_ruby_platform true"

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack'
      G

      bundle :install, :quiet => true
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
        source "#{file_uri_for(gem_repo1)}"
        gem 'non-existing-gem'
      G

      bundle :install, :quiet => true, :raise_on_error => false, :env => { "RUBYOPT" => "-r#{bundled_app("install_with_warning.rb")}" }
      expect(out).to be_empty
      expect(err).to include("Could not find gem 'non-existing-gem'")
      expect(err).to include("BOOOOO")
    end
  end

  describe "when bundle path does not have write access", :permissions do
    let(:bundle_path) { bundled_app("vendor") }

    before do
      FileUtils.mkdir_p(bundle_path)
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack'
      G
    end

    it "should display a proper message to explain the problem" do
      FileUtils.chmod(0o500, bundle_path)

      bundle "config set --local path vendor"
      bundle :install, :raise_on_error => false
      expect(err).to include(bundle_path.to_s)
      expect(err).to include("grant write permissions")
    end
  end

  describe "when bundle gems path does not have write access", :permissions do
    let(:gems_path) { bundled_app("vendor/#{Bundler.ruby_scope}/gems") }

    before do
      FileUtils.mkdir_p(gems_path)
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack'
      G
    end

    it "should display a proper message to explain the problem" do
      FileUtils.chmod("-x", gems_path)
      bundle "config set --local path vendor"

      begin
        bundle :install, :raise_on_error => false
      ensure
        FileUtils.chmod("+x", gems_path)
      end

      expect(err).not_to include("ERROR REPORT TEMPLATE")

      expect(err).to include(
        "There was an error while trying to create `#{gems_path.join("rack-1.0.0")}`. " \
        "It is likely that you need to grant executable permissions for all parent directories and write permissions for `#{gems_path}`."
      )
    end
  end

  describe "when the path of a specific gem is not writable", :permissions do
    let(:gems_path) { bundled_app("vendor/#{Bundler.ruby_scope}/gems") }
    let(:foo_path) { gems_path.join("foo-1.0.0") }

    before do
      build_repo4 do
        build_gem "foo", "1.0.0" do |s|
          s.write "CHANGELOG.md", "foo"
        end
      end

      gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
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
        bundle "install --redownload", :raise_on_error => false
      ensure
        FileUtils.chmod("+x", foo_path)
      end

      expect(err).not_to include("ERROR REPORT TEMPLATE")

      expect(err).to include(
        "There was an error while trying to delete `#{foo_path}`. " \
        "It is likely that you need to grant executable permissions for all parent directories " \
        "and write permissions for `#{gems_path}`, and the same thing for all subdirectories inside #{foo_path}."
      )
    end
  end

  describe "when bundle cache path does not have write access", :permissions do
    let(:cache_path) { bundled_app("vendor/#{Bundler.ruby_scope}/cache") }

    before do
      FileUtils.mkdir_p(cache_path)
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack'
      G
    end

    it "should display a proper message to explain the problem" do
      FileUtils.chmod(0o500, cache_path)

      bundle "config set --local path vendor"
      bundle :install, :raise_on_error => false
      expect(err).to include(cache_path.to_s)
      expect(err).to include("grant write permissions")
    end
  end

  context "after installing with --standalone" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
      bundle "config set --local path bundle"
      bundle "install", :standalone => true
    end

    it "includes the standalone path" do
      bundle "binstubs rack", :standalone => true
      standalone_line = File.read(bundled_app("bin/rackup")).each_line.find {|line| line.include? "$:.unshift" }.strip
      expect(standalone_line).to eq %($:.unshift File.expand_path "../../bundle", path.realpath)
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
      bundle :install, :env => { "BUNDLE_RUBYGEMS__ORG" => "user:pass{word" }, :raise_on_error => false
      expect(exitstatus).to eq(17)
      expect(err).to eq("Please CGI escape your usernames and passwords before " \
                        "setting them for authentication.")
    end
  end

  context "in a frozen bundle" do
    before do
      build_repo4 do
        build_gem "libv8", "8.4.255.0" do |s|
          s.platform = "x86_64-darwin-19"
        end
      end

      gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"

        gem "libv8"
      G

      lockfile <<-L
        GEM
          remote: #{file_uri_for(gem_repo4)}/
          specs:
            libv8 (8.4.255.0-x86_64-darwin-19)

        PLATFORMS
          x86_64-darwin-19

        DEPENDENCIES
          libv8

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "config set --local deployment true"
    end

    it "should fail loudly if the lockfile platforms don't include the current platform" do
      simulate_platform(Gem::Platform.new("x86_64-linux")) { bundle "install", :raise_on_error => false }

      expect(err).to eq(
        "Your bundle only supports platforms [\"x86_64-darwin-19\"] but your local platform is x86_64-linux. " \
        "Add the current platform to the lockfile with `bundle lock --add-platform x86_64-linux` and try again."
      )
    end
  end

  context "with missing platform specific gems in lockfile" do
    before do
      build_repo4 do
        build_gem "racc", "1.5.2"

        build_gem "nokogiri", "1.12.4" do |s|
          s.platform = "x86_64-darwin"
          s.add_runtime_dependency "racc", "~> 1.4"
        end

        build_gem "nokogiri", "1.12.4" do |s|
          s.platform = "x86_64-linux"
          s.add_runtime_dependency "racc", "~> 1.4"
        end

        build_gem "crass", "1.0.6"

        build_gem "loofah", "2.12.0" do |s|
          s.add_runtime_dependency "crass", "~> 1.0.2"
          s.add_runtime_dependency "nokogiri", ">= 1.5.9"
        end
      end

      gemfile <<-G
        source "https://gem.repo4"

        ruby "#{RUBY_VERSION}"

        gem "loofah", "~> 2.12.0"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo4/
          specs:
            crass (1.0.6)
            loofah (2.12.0)
              crass (~> 1.0.2)
              nokogiri (>= 1.5.9)
            nokogiri (1.12.4-x86_64-darwin)
              racc (~> 1.4)
            racc (1.5.2)

        PLATFORMS
          x86_64-darwin-20
          x86_64-linux

        DEPENDENCIES
          loofah (~> 2.12.0)

        RUBY VERSION
           #{Bundler::RubyVersion.system}

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end

    it "automatically fixes the lockfile" do
      bundle "config set --local path vendor/bundle"

      simulate_platform "x86_64-linux" do
        bundle "install", :artifice => "compact_index"
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
              racc (~> 1.4)
            nokogiri (1.12.4-x86_64-linux)
              racc (~> 1.4)
            racc (1.5.2)

        PLATFORMS
          x86_64-darwin-20
          x86_64-linux

        DEPENDENCIES
          loofah (~> 2.12.0)

        RUBY VERSION
           #{Bundler::RubyVersion.system}

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end
  end

  context "with --local flag" do
    before do
      system_gems "rack-1.0.0", :path => default_bundle_path
    end

    it "respects installed gems without fetching any remote sources" do
      install_gemfile <<-G, :local => true
        source "#{file_uri_for(gem_repo1)}"

        source "https://not-existing-source" do
          gem "rack"
        end
      G

      expect(last_command).to be_success
    end
  end
end
