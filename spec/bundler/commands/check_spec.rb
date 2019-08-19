# frozen_string_literal: true

RSpec.describe "bundle check" do
  it "returns success when the Gemfile is satisfied" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rails"
    G

    bundle :check
    expect(exitstatus).to eq(0) if exitstatus
    expect(out).to include("The Gemfile's dependencies are satisfied")
  end

  it "works with the --gemfile flag when not in the directory" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rails"
    G

    Dir.chdir tmp
    bundle "check --gemfile bundled_app/Gemfile"
    expect(out).to include("The Gemfile's dependencies are satisfied")
  end

  it "creates a Gemfile.lock by default if one does not exist" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rails"
    G

    FileUtils.rm("Gemfile.lock")

    bundle "check"

    expect(bundled_app("Gemfile.lock")).to exist
  end

  it "does not create a Gemfile.lock if --dry-run was passed" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rails"
    G

    FileUtils.rm("Gemfile.lock")

    bundle "check --dry-run"

    expect(bundled_app("Gemfile.lock")).not_to exist
  end

  it "prints a generic error if the missing gems are unresolvable" do
    system_gems ["rails-2.3.2"]

    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rails"
    G

    bundle :check
    expect(out).to include("Bundler can't satisfy your Gemfile's dependencies.")
  end

  it "prints a generic error if a Gemfile.lock does not exist and a toplevel dependency does not exist" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rails"
    G

    bundle :check
    expect(exitstatus).to be > 0 if exitstatus
    expect(out).to include("Bundler can't satisfy your Gemfile's dependencies.")
  end

  it "prints a generic message if you changed your lockfile" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem 'rails'
    G
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem 'rails_fail'
    G

    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rails"
      gem "rails_fail"
    G

    bundle :check
    expect(out).to include("Bundler can't satisfy your Gemfile's dependencies.")
  end

  it "remembers --without option from install", :bundler => "< 2" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      group :foo do
        gem "rack"
      end
    G

    bundle! "install --without foo"
    bundle! "check"
    expect(out).to include("The Gemfile's dependencies are satisfied")
  end

  it "uses the without setting" do
    bundle! "config without foo"
    install_gemfile! <<-G
      source "file://#{gem_repo1}"
      group :foo do
        gem "rack"
      end
    G

    bundle! "check"
    expect(out).to include("The Gemfile's dependencies are satisfied")
  end

  it "ensures that gems are actually installed and not just cached" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack", :group => :foo
    G

    bundle :install, forgotten_command_line_options(:without => "foo")

    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    bundle "check"
    expect(out).to include("* rack (1.0.0)")
    expect(exitstatus).to eq(1) if exitstatus
  end

  it "ignores missing gems restricted to other platforms" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
      platforms :#{not_local_tag} do
        gem "activesupport"
      end
    G

    system_gems "rack-1.0.0", :path => :bundle_path

    lockfile <<-G
      GEM
        remote: file:#{gem_repo1}/
        specs:
          activesupport (2.3.5)
          rack (1.0.0)

      PLATFORMS
        #{local}
        #{not_local}

      DEPENDENCIES
        rack
        activesupport
    G

    bundle :check
    expect(out).to include("The Gemfile's dependencies are satisfied")
  end

  it "works with env conditionals" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
      env :NOT_GOING_TO_BE_SET do
        gem "activesupport"
      end
    G

    system_gems "rack-1.0.0", :path => :bundle_path

    lockfile <<-G
      GEM
        remote: file:#{gem_repo1}/
        specs:
          activesupport (2.3.5)
          rack (1.0.0)

      PLATFORMS
        #{local}
        #{not_local}

      DEPENDENCIES
        rack
        activesupport
    G

    bundle :check
    expect(out).to include("The Gemfile's dependencies are satisfied")
  end

  it "outputs an error when the default Gemfile is not found" do
    bundle :check
    expect(exitstatus).to eq(10) if exitstatus
    expect(out).to include("Could not locate Gemfile")
  end

  it "does not output fatal error message" do
    bundle :check
    expect(exitstatus).to eq(10) if exitstatus
    expect(out).not_to include("Unfortunately, a fatal error has occurred. ")
  end

  it "should not crash when called multiple times on a new machine" do
    gemfile <<-G
      gem 'rails', '3.0.0.beta3'
      gem 'paperclip', :git => 'git://github.com/thoughtbot/paperclip.git'
    G

    simulate_new_machine
    bundle "check"
    last_out = out
    3.times do
      bundle :check
      expect(out).to eq(last_out)
    end
  end

  it "fails when there's no lock file and frozen is set" do
    install_gemfile! <<-G
      source "file://#{gem_repo1}"
      gem "foo"
    G

    bundle! "install", forgotten_command_line_options(:deployment => true)
    FileUtils.rm(bundled_app("Gemfile.lock"))

    bundle :check
    expect(last_command).to be_failure
  end

  context "--path", :bundler => "< 2" do
    before do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rails"
      G
      bundle "install --path vendor/bundle"

      FileUtils.rm_rf(bundled_app(".bundle"))
    end

    it "returns success" do
      bundle! "check --path vendor/bundle"
      expect(out).to include("The Gemfile's dependencies are satisfied")
    end

    it "should write to .bundle/config", :bundler => "< 2" do
      bundle "check --path vendor/bundle"
      bundle! "check"
    end
  end

  context "--path vendor/bundle after installing gems in the default directory" do
    it "returns false" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rails"
      G

      bundle "check --path vendor/bundle"
      expect(exitstatus).to eq(1) if exitstatus
      expect(out).to match(/The following gems are missing/)
    end
  end

  describe "when locked" do
    before :each do
      system_gems "rack-1.0.0"
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", "1.0"
      G
    end

    it "returns success when the Gemfile is satisfied" do
      bundle :install
      bundle :check
      expect(exitstatus).to eq(0) if exitstatus
      expect(out).to include("The Gemfile's dependencies are satisfied")
    end

    it "shows what is missing with the current Gemfile if it is not satisfied" do
      simulate_new_machine
      bundle :check
      expect(out).to match(/The following gems are missing/)
      expect(out).to include("* rack (1.0")
    end
  end

  describe "BUNDLED WITH" do
    def lock_with(bundler_version = nil)
      lock = <<-L
        GEM
          remote: file:#{gem_repo1}/
          specs:
            rack (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          rack
      L

      if bundler_version
        lock += "\n        BUNDLED WITH\n           #{bundler_version}\n"
      end

      lock
    end

    before do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G
    end

    context "is not present" do
      it "does not change the lock" do
        lockfile lock_with(nil)
        bundle :check
        lockfile_should_be lock_with(nil)
      end
    end

    context "is newer" do
      it "does not change the lock but warns" do
        lockfile lock_with(Bundler::VERSION.succ)
        bundle! :check
        expect(last_command.bundler_err).to include("the running version of Bundler (#{Bundler::VERSION}) is older than the version that created the lockfile (#{Bundler::VERSION.succ})")
        lockfile_should_be lock_with(Bundler::VERSION.succ)
      end
    end

    context "is older" do
      it "does not change the lock" do
        lockfile lock_with("1.10.1")
        bundle :check
        lockfile_should_be lock_with("1.10.1")
      end
    end
  end
end
