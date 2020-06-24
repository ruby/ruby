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
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
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
        bundle "config --local path vendor"
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
      build_repo2
      update_repo2

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

      expect(err).to include("Your Gemfile has no gem server sources")
    end

    it "creates a Gemfile.lock on a blank Gemfile" do
      install_gemfile <<-G
      G

      expect(File.exist?(bundled_app_lock)).to eq(true)
    end

    context "throws a warning if a gem is added twice in Gemfile" do
      it "without version requirements" do
        install_gemfile <<-G, :raise_on_error => false
          source "#{file_uri_for(gem_repo2)}"
          gem "rack"
          gem "rack"
        G

        expect(err).to include("Your Gemfile lists the gem rack (>= 0) more than once.")
        expect(err).to include("Remove any duplicate entries and specify the gem only once.")
        expect(err).to include("While it's not a problem now, it could cause errors if you change the version of one of them later.")
      end

      it "with same versions" do
        install_gemfile <<-G, :raise_on_error => false
          source "#{file_uri_for(gem_repo2)}"
          gem "rack", "1.0"
          gem "rack", "1.0"
        G

        expect(err).to include("Your Gemfile lists the gem rack (= 1.0) more than once.")
        expect(err).to include("Remove any duplicate entries and specify the gem only once.")
        expect(err).to include("While it's not a problem now, it could cause errors if you change the version of one of them later.")
      end
    end

    context "throws an error if a gem is added twice in Gemfile" do
      it "when version of one dependency is not specified" do
        install_gemfile <<-G, :raise_on_error => false
          source "#{file_uri_for(gem_repo2)}"
          gem "rack"
          gem "rack", "1.0"
        G

        expect(err).to include("You cannot specify the same gem twice with different version requirements")
        expect(err).to include("You specified: rack (>= 0) and rack (= 1.0).")
      end

      it "when different versions of both dependencies are specified" do
        install_gemfile <<-G, :raise_on_error => false
          source "#{file_uri_for(gem_repo2)}"
          gem "rack", "1.0"
          gem "rack", "1.1"
        G

        expect(err).to include("You cannot specify the same gem twice with different version requirements")
        expect(err).to include("You specified: rack (= 1.0) and rack (= 1.1).")
      end
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
        and include("Make sure that `gem install ajp-rails -v '0.0.0' --source '#{file_uri_for(gem_repo2)}/'` succeeds before bundling.")
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
          ::RUBY_VERSION = '2.0.1'
          ruby '~> 2.2'
        G
        expect(err).to include("Your Ruby version is 2.0.1, but your Gemfile specified ~> 2.2")
      end
    end

    context "and using a supported Ruby version" do
      before do
        install_gemfile <<-G
          ::RUBY_VERSION = '2.1.3'
          ::RUBY_PATCHLEVEL = 100
          ruby '~> 2.1.0'
        G
      end

      it "writes current Ruby version to Gemfile.lock" do
        lockfile_should_be <<-L
         GEM
           specs:

         PLATFORMS
           #{lockfile_platforms}

         DEPENDENCIES

         RUBY VERSION
            ruby 2.1.3p100

         BUNDLED WITH
            #{Bundler::VERSION}
        L
      end

      it "updates Gemfile.lock with updated incompatible ruby version" do
        install_gemfile <<-G
          ::RUBY_VERSION = '2.2.3'
          ::RUBY_PATCHLEVEL = 100
          ruby '~> 2.2.0'
        G

        lockfile_should_be <<-L
         GEM
           specs:

         PLATFORMS
           #{lockfile_platforms}

         DEPENDENCIES

         RUBY VERSION
            ruby 2.2.3p100

         BUNDLED WITH
            #{Bundler::VERSION}
        L
      end
    end
  end

  describe "when Bundler root contains regex chars" do
    it "doesn't blow up" do
      root_dir = tmp("foo[]bar")

      FileUtils.mkdir_p(root_dir)

      build_lib "foo"
      gemfile = <<-G
        gem 'foo', :path => "#{lib_path("foo-1.0")}"
      G
      File.open("#{root_dir}/Gemfile", "w") do |file|
        file.puts gemfile
      end

      bundle :install, :dir => root_dir
    end
  end

  describe "when requesting a quiet install via --quiet" do
    it "should be quiet" do
      bundle "config set force_ruby_platform true"

      gemfile <<-G
        gem 'rack'
      G

      bundle :install, :quiet => true, :raise_on_error => false
      expect(err).to include("Could not find gem 'rack'")
      expect(err).to_not include("Your Gemfile has no gem server sources")
    end
  end

  describe "when bundle path does not have write access", :permissions do
    before do
      FileUtils.mkdir_p(bundled_app("vendor"))
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack'
      G
    end

    it "should display a proper message to explain the problem" do
      FileUtils.chmod(0o500, bundled_app("vendor"))

      bundle "config --local path vendor"
      bundle :install, :raise_on_error => false
      expect(err).to include(bundled_app("vendor").to_s)
      expect(err).to include("grant write permissions")
    end
  end

  context "after installing with --standalone" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
      bundle "config --local path bundle"
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
end
