# frozen_string_literal: true

RSpec.describe "Self management" do
  describe "auto switching" do
    let(:previous_minor) do
      "9.3.0"
    end

    let(:current_version) do
      "9.4.0"
    end

    around do |example|
      build_repo4 do
        build_bundler previous_minor

        build_bundler current_version

        build_gem "myrack", "1.0.0"
      end

      gemfile <<-G
        source "https://gem.repo4"

        gem "myrack"
      G

      pristine_system_gems "bundler-#{current_version}"

      with_env_vars("BUNDLER_4_MODE" => nil, &example)
    end

    it "installs locked version when using system path and uses it" do
      lockfile_bundled_with(previous_minor)

      bundle "config set --local path.system true"
      bundle "install"
      expect(out).to include("Bundler #{current_version} is running, but your lockfile was generated with #{previous_minor}. Installing Bundler #{previous_minor} and restarting using that version.")

      # It uninstalls the older system bundler
      bundle "clean --force", artifice: nil
      expect(out).to eq("Removing bundler (#{current_version})")

      # App now uses locked version
      bundle "-v", artifice: nil
      expect(out).to eq(previous_minor)

      # ruby-core test setup has always "lib" in $LOAD_PATH so `require "bundler/setup"` always activate the local version rather than using RubyGems gem activation stuff
      unless ruby_core?
        # App now uses locked version, even when not using the CLI directly
        file = bundled_app("bin/bundle_version.rb")
        create_file file, <<-RUBY
          #!#{Gem.ruby}
          require 'bundler/setup'
          puts '#{previous_minor}'
        RUBY
        file.chmod(0o777)
        cmd = Gem.win_platform? ? "#{Gem.ruby} bin/bundle_version.rb" : "bin/bundle_version.rb"
        sys_exec cmd, artifice: nil
        expect(out).to eq(previous_minor)
      end

      # Subsequent installs use the locked version without reinstalling
      bundle "install --verbose", artifice: nil
      expect(out).to include("Using bundler #{previous_minor}")
      expect(out).not_to include("Bundler #{current_version} is running, but your lockfile was generated with #{previous_minor}. Installing Bundler #{previous_minor} and restarting using that version.")
    end

    it "installs locked version when using local path and uses it" do
      lockfile_bundled_with(previous_minor)

      bundle "config set --local path vendor/bundle"
      bundle "install"
      expect(out).to include("Bundler #{current_version} is running, but your lockfile was generated with #{previous_minor}. Installing Bundler #{previous_minor} and restarting using that version.")
      expect(vendored_gems("gems/bundler-#{previous_minor}")).to exist

      # It does not uninstall the locked bundler
      bundle "clean"
      expect(out).to be_empty

      # App now uses locked version
      bundle "-v"
      expect(out).to eq(previous_minor)

      # ruby-core test setup has always "lib" in $LOAD_PATH so `require "bundler/setup"` always activate the local version rather than using RubyGems gem activation stuff
      unless ruby_core?
        # App now uses locked version, even when not using the CLI directly
        file = bundled_app("bin/bundle_version.rb")
        create_file file, <<-RUBY
          #!#{Gem.ruby}
          require 'bundler/setup'
          puts '#{previous_minor}'
        RUBY
        file.chmod(0o777)
        cmd = Gem.win_platform? ? "#{Gem.ruby} bin/bundle_version.rb" : "bin/bundle_version.rb"
        sys_exec cmd, artifice: nil
        expect(out).to eq(previous_minor)
      end

      # Subsequent installs use the locked version without reinstalling
      bundle "install --verbose"
      expect(out).to include("Using bundler #{previous_minor}")
      expect(out).not_to include("Bundler #{current_version} is running, but your lockfile was generated with #{previous_minor}. Installing Bundler #{previous_minor} and restarting using that version.")
    end

    it "installs locked version when using deployment option and uses it" do
      lockfile_bundled_with(previous_minor)

      bundle "config set --local deployment true"
      bundle "install"
      expect(out).to include("Bundler #{current_version} is running, but your lockfile was generated with #{previous_minor}. Installing Bundler #{previous_minor} and restarting using that version.")
      expect(vendored_gems("gems/bundler-#{previous_minor}")).to exist

      # It does not uninstall the locked bundler
      bundle "clean"
      expect(out).to be_empty

      # App now uses locked version
      bundle "-v"
      expect(out).to eq(previous_minor)

      # Subsequent installs use the locked version without reinstalling
      bundle "install --verbose"
      expect(out).to include("Using bundler #{previous_minor}")
      expect(out).not_to include("Bundler #{current_version} is running, but your lockfile was generated with #{previous_minor}. Installing Bundler #{previous_minor} and restarting using that version.")
    end

    it "does not try to install a development version" do
      lockfile_bundled_with("#{previous_minor}.dev")

      bundle "install --verbose"
      expect(out).not_to match(/restarting using that version/)

      bundle "-v"
      expect(out).to eq(current_version)
    end

    it "does not try to install when --local is passed" do
      lockfile_bundled_with(previous_minor)
      system_gems "myrack-1.0.0", path: local_gem_path

      bundle "install --local"
      expect(out).not_to match(/Installing Bundler/)

      bundle "-v"
      expect(out).to eq(current_version)
    end

    it "shows a discrete message if locked bundler does not exist" do
      missing_minor = "#{current_version[0]}.999.999"

      lockfile_bundled_with(missing_minor)

      bundle "install"
      expect(err).to eq("Your lockfile is locked to a version of bundler (#{missing_minor}) that doesn't exist at https://rubygems.org/. Going on using #{current_version}")

      bundle "-v"
      expect(out).to eq(current_version)
    end

    it "installs BUNDLE_VERSION version when using bundle config version x.y.z" do
      lockfile_bundled_with(current_version)

      bundle "config set --local version #{previous_minor}"
      bundle "install"
      expect(out).to include("Bundler #{current_version} is running, but your configuration was #{previous_minor}. Installing Bundler #{previous_minor} and restarting using that version.")

      bundle "-v"
      expect(out).to eq(previous_minor)
    end

    it "does not try to install when using bundle config version global" do
      lockfile_bundled_with(previous_minor)

      bundle "config set version system"
      bundle "install"
      expect(out).not_to match(/restarting using that version/)

      bundle "-v"
      expect(out).to eq(current_version)
    end

    it "does not try to install when using bundle config version <dev-version>" do
      lockfile_bundled_with(previous_minor)

      bundle "config set version #{previous_minor}.dev"
      bundle "install"
      expect(out).not_to match(/restarting using that version/)

      bundle "-v"
      expect(out).to eq(current_version)
    end

    it "ignores malformed lockfile version" do
      lockfile_bundled_with("2.3.")

      bundle "install --verbose"
      expect(out).to include("Using bundler #{current_version}")
    end

    it "uses the right original script when re-execing, if `$0` has been changed to something that's not a script", :ruby_repo do
      system_gems "bundler-9.9.9", path: local_gem_path

      test = bundled_app("test.rb")

      create_file test, <<~RUBY
        $0 = "this is the program name"
        require "bundler/setup"
      RUBY

      lockfile_bundled_with("9.9.9")

      sys_exec "#{Gem.ruby} #{test}", artifice: nil, raise_on_error: false
      expect(err).to include("Could not find myrack-1.0.0")
      expect(err).not_to include("this is the program name")
    end

    it "uses modified $0 when re-execing, if `$0` has been changed to a script", :ruby_repo do
      system_gems "bundler-9.9.9", path: local_gem_path

      runner = bundled_app("runner.rb")

      create_file runner, <<~RUBY
        $0 = ARGV.shift
        load $0
      RUBY

      script = bundled_app("script.rb")
      create_file script, <<~RUBY
        require "bundler/setup"
      RUBY

      lockfile_bundled_with("9.9.9")

      sys_exec "#{Gem.ruby} #{runner} #{script}", artifice: nil, raise_on_error: false
      expect(err).to include("Could not find myrack-1.0.0")
    end

    private

    def lockfile_bundled_with(version)
      lockfile <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            myrack (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          myrack

        BUNDLED WITH
           #{version}
      L
    end
  end
end
