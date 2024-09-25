# frozen_string_literal: true

RSpec.describe "bundle check" do
  it "returns success when the Gemfile is satisfied" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "rails"
    G

    bundle :check
    expect(out).to include("The Gemfile's dependencies are satisfied")
  end

  it "works with the --gemfile flag when not in the directory" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "rails"
    G

    bundle "check --gemfile bundled_app/Gemfile", dir: tmp
    expect(out).to include("The Gemfile's dependencies are satisfied")
  end

  it "creates a Gemfile.lock by default if one does not exist" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "rails"
    G

    FileUtils.rm(bundled_app_lock)

    bundle "check"

    expect(bundled_app_lock).to exist
  end

  it "does not create a Gemfile.lock if --dry-run was passed" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "rails"
    G

    FileUtils.rm(bundled_app_lock)

    bundle "check --dry-run"

    expect(bundled_app_lock).not_to exist
  end

  it "prints a generic error if the missing gems are unresolvable" do
    system_gems ["rails-2.3.2"]

    gemfile <<-G
      source "https://gem.repo1"
      gem "rails"
    G

    bundle :check, raise_on_error: false
    expect(err).to include("Bundler can't satisfy your Gemfile's dependencies.")
  end

  it "prints a generic error if a Gemfile.lock does not exist and a toplevel dependency does not exist" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "rails"
    G

    bundle :check, raise_on_error: false
    expect(exitstatus).to be > 0
    expect(err).to include("Bundler can't satisfy your Gemfile's dependencies.")
  end

  it "prints a generic error if gem git source is not checked out" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "rails", git: "git@github.com:rails/rails.git"
    G

    bundle :check, raise_on_error: false
    expect(exitstatus).to eq 1
    expect(err).to include("Bundler can't satisfy your Gemfile's dependencies.")
  end

  it "prints a generic message if you changed your lockfile" do
    build_repo2 do
      build_gem "rails_pinned_to_old_activesupport" do |s|
        s.add_dependency "activesupport", "= 1.2.3"
      end
    end

    install_gemfile <<-G
      source "https://gem.repo2"
      gem 'rails'
    G

    gemfile <<-G
      source "https://gem.repo2"
      gem "rails"
      gem "rails_pinned_to_old_activesupport"
    G

    bundle :check, raise_on_error: false
    expect(err).to include("Bundler can't satisfy your Gemfile's dependencies.")
  end

  it "remembers --without option from install", bundler: "< 3" do
    gemfile <<-G
      source "https://gem.repo1"
      group :foo do
        gem "myrack"
      end
    G

    bundle "install --without foo"
    bundle "check"
    expect(out).to include("The Gemfile's dependencies are satisfied")
  end

  it "uses the without setting" do
    bundle "config set without foo"
    install_gemfile <<-G
      source "https://gem.repo1"
      group :foo do
        gem "myrack"
      end
    G

    bundle "check"
    expect(out).to include("The Gemfile's dependencies are satisfied")
  end

  it "ensures that gems are actually installed and not just cached" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack", :group => :foo
    G

    bundle "config set --local without foo"
    bundle :install

    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    bundle "check", raise_on_error: false
    expect(err).to include("* myrack (1.0.0)")
    expect(exitstatus).to eq(1)
  end

  it "ensures that gems are actually installed and not just cached in applications' cache" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    bundle "config set --local path vendor/bundle"
    bundle :cache

    gem_command "uninstall myrack", env: { "GEM_HOME" => vendored_gems.to_s }

    bundle "check", raise_on_error: false
    expect(err).to include("* myrack (1.0.0)")
    expect(exitstatus).to eq(1)
  end

  it "ignores missing gems restricted to other platforms" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
      platforms :#{not_local_tag} do
        gem "activesupport"
      end
    G

    system_gems "myrack-1.0.0", path: default_bundle_path

    lockfile <<-G
      GEM
        remote: https://gem.repo1/
        specs:
          activesupport (2.3.5)
          myrack (1.0.0)

      PLATFORMS
        #{generic_local_platform}
        #{not_local}

      DEPENDENCIES
        myrack
        activesupport
    G

    bundle :check
    expect(out).to include("The Gemfile's dependencies are satisfied")
  end

  it "works with env conditionals" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
      env :NOT_GOING_TO_BE_SET do
        gem "activesupport"
      end
    G

    system_gems "myrack-1.0.0", path: default_bundle_path

    lockfile <<-G
      GEM
        remote: https://gem.repo1/
        specs:
          activesupport (2.3.5)
          myrack (1.0.0)

      PLATFORMS
        #{generic_local_platform}
        #{not_local}

      DEPENDENCIES
        myrack
        activesupport
    G

    bundle :check
    expect(out).to include("The Gemfile's dependencies are satisfied")
  end

  it "outputs an error when the default Gemfile is not found" do
    bundle :check, raise_on_error: false
    expect(exitstatus).to eq(10)
    expect(err).to include("Could not locate Gemfile")
  end

  it "does not output fatal error message" do
    bundle :check, raise_on_error: false
    expect(exitstatus).to eq(10)
    expect(err).not_to include("Unfortunately, a fatal error has occurred. ")
  end

  it "fails when there's no lock file and frozen is set" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo"
    G

    bundle "config set --local deployment true"
    bundle "install"
    FileUtils.rm(bundled_app_lock)

    bundle :check, raise_on_error: false
    expect(last_command).to be_failure
  end

  context "--path", bundler: "< 3" do
    context "after installing gems in the proper directory" do
      before do
        gemfile <<-G
          source "https://gem.repo1"
          gem "rails"
        G
        bundle "install --path vendor/bundle"

        FileUtils.rm_rf(bundled_app(".bundle"))
      end

      it "returns success" do
        bundle "check --path vendor/bundle"
        expect(out).to include("The Gemfile's dependencies are satisfied")
      end

      it "should write to .bundle/config" do
        bundle "check --path vendor/bundle"
        bundle "check"
      end
    end

    context "after installing gems on a different directory" do
      before do
        install_gemfile <<-G
          source "https://gem.repo1"
          gem "rails"
        G

        bundle "check --path vendor/bundle", raise_on_error: false
      end

      it "returns false" do
        expect(exitstatus).to eq(1)
        expect(err).to match(/The following gems are missing/)
      end
    end
  end

  describe "when locked" do
    before :each do
      system_gems "myrack-1.0.0"
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", "1.0"
      G
    end

    it "returns success when the Gemfile is satisfied" do
      bundle :install
      bundle :check
      expect(out).to include("The Gemfile's dependencies are satisfied")
    end

    it "shows what is missing with the current Gemfile if it is not satisfied" do
      simulate_new_machine
      bundle :check, raise_on_error: false
      expect(err).to match(/The following gems are missing/)
      expect(err).to include("* myrack (1.0")
    end
  end

  describe "when locked with multiple dependents with different requirements" do
    before :each do
      build_repo4 do
        build_gem "depends_on_myrack" do |s|
          s.add_dependency "myrack", ">= 1.0"
        end
        build_gem "also_depends_on_myrack" do |s|
          s.add_dependency "myrack", "~> 1.0"
        end
        build_gem "myrack"
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem "depends_on_myrack"
        gem "also_depends_on_myrack"
      G

      bundle "lock"
    end

    it "shows what is missing with the current Gemfile without duplications" do
      bundle :check, raise_on_error: false
      expect(err).to match(/The following gems are missing/)
      expect(err).to include("* myrack (1.0").once
    end
  end

  describe "when locked under multiple platforms" do
    before :each do
      build_repo4 do
        build_gem "myrack"
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem "myrack"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo4/
          specs:
            myrack (1.0)

        PLATFORMS
          ruby
          #{local_platform}

        DEPENDENCIES
          myrack

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end

    it "shows what is missing with the current Gemfile without duplications" do
      bundle :check, raise_on_error: false
      expect(err).to match(/The following gems are missing/)
      expect(err).to include("* myrack (1.0").once
    end
  end

  describe "when using only scoped rubygems sources" do
    before do
      gemfile <<~G
        source "https://gem.repo2"
        source "https://gem.repo1" do
          gem "myrack"
        end
      G
    end

    it "returns success when the Gemfile is satisfied" do
      system_gems "myrack-1.0.0", path: default_bundle_path
      bundle :check
      expect(out).to include("The Gemfile's dependencies are satisfied")
    end
  end

  describe "when using only scoped rubygems sources with indirect dependencies" do
    before do
      build_repo4 do
        build_gem "depends_on_myrack" do |s|
          s.add_dependency "myrack"
        end

        build_gem "myrack"
      end

      gemfile <<~G
        source "https://gem.repo1"
        source "https://gem.repo4" do
          gem "depends_on_myrack"
        end
      G
    end

    it "returns success when the Gemfile is satisfied and generates a correct lockfile" do
      system_gems "depends_on_myrack-1.0", "myrack-1.0", gem_repo: gem_repo4, path: default_bundle_path
      bundle :check

      checksums = checksums_section_when_enabled do |c|
        c.no_checksum "depends_on_myrack", "1.0"
        c.no_checksum "myrack", "1.0"
      end

      expect(out).to include("The Gemfile's dependencies are satisfied")
      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo1/
          specs:

        GEM
          remote: https://gem.repo4/
          specs:
            depends_on_myrack (1.0)
              myrack
            myrack (1.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          depends_on_myrack!
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end
  end

  context "with gemspec directive and scoped sources" do
    before do
      build_repo4 do
        build_gem "awesome_print"
      end

      build_repo2 do
        build_gem "dex-dispatch-engine"
      end

      build_lib("bundle-check-issue", path: tmp("bundle-check-issue")) do |s|
        s.write "Gemfile", <<-G
          source "https://localgemserver.test"

          gemspec

          source "https://localgemserver.test/extra" do
            gem "dex-dispatch-engine"
          end
        G

        s.add_dependency "awesome_print"
      end

      bundle "install", artifice: "compact_index_extra", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }, dir: tmp("bundle-check-issue")
    end

    it "does not corrupt lockfile when changing version" do
      version_file = tmp("bundle-check-issue/bundle-check-issue.gemspec")
      File.write(version_file, File.read(version_file).gsub(/s\.version = .+/, "s.version = '9999'"))

      bundle "check --verbose", dir: tmp("bundle-check-issue")

      lockfile = File.read(tmp("bundle-check-issue/Gemfile.lock"))

      checksums = checksums_section_when_enabled(lockfile) do |c|
        c.checksum gem_repo4, "awesome_print", "1.0"
        c.no_checksum "bundle-check-issue", "9999"
        c.checksum gem_repo2, "dex-dispatch-engine", "1.0"
      end

      expect(lockfile).to eq <<~L
        PATH
          remote: .
          specs:
            bundle-check-issue (9999)
              awesome_print

        GEM
          remote: https://localgemserver.test/
          specs:
            awesome_print (1.0)

        GEM
          remote: https://localgemserver.test/extra/
          specs:
            dex-dispatch-engine (1.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          bundle-check-issue!
          dex-dispatch-engine!
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end
  end

  describe "BUNDLED WITH" do
    def lock_with(bundler_version = nil)
      lock = <<~L
        GEM
          remote: https://gem.repo1/
          specs:
            myrack (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          myrack
      L

      if bundler_version
        lock += "\nBUNDLED WITH\n   #{bundler_version}\n"
      end

      lock
    end

    before do
      bundle "config set --local path vendor/bundle"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
    end

    context "is not present" do
      it "does not change the lock" do
        lockfile lock_with(nil)
        bundle :check
        expect(lockfile).to eq lock_with(nil)
      end
    end

    context "is newer" do
      it "does not change the lock and does not warn" do
        lockfile lock_with(Bundler::VERSION.succ)
        bundle :check
        expect(err).to be_empty
        expect(lockfile).to eq lock_with(Bundler::VERSION.succ)
      end
    end

    context "is older" do
      it "does not change the lock" do
        system_gems "bundler-1.18.0"
        lockfile lock_with("1.18.0")
        bundle :check
        expect(lockfile).to eq lock_with("1.18.0")
      end
    end
  end
end
