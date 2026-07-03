# frozen_string_literal: true

RSpec.describe "bundle outdated" do
  it "performs an automatic bundle install" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack", "0.9.1"
      gem "foo"
    G

    bundle_config "auto_install 1"
    bundle :outdated, raise_on_error: false
    expect(out).to include("Installing foo 1.0")
  end

  context "in deployment mode" do
    before do
      build_repo2

      gemfile <<-G
        source "https://gem.repo2"

        gem "myrack"
        gem "foo"
      G
      bundle :lock
      bundle_config "deployment true"
    end

    it "outputs a helpful message about being in deployment mode" do
      update_repo2 { build_gem "activesupport", "3.0" }

      bundle "outdated", raise_on_error: false
      expect(last_command).to be_failure
      expect(err).to include("You are trying to check outdated gems in deployment mode.")
      expect(err).to include("Run `bundle outdated` elsewhere.")
      expect(err).to include("If this is a development machine, remove the ")
      expect(err).to include("Gemfile freeze\nby running `bundle config unset deployment`.")
    end
  end

  context "after bundle config set --local deployment true" do
    before do
      build_repo2 do
        build_git "foo", path: lib_path("foo")
        build_git "zebra", path: lib_path("zebra")
      end

      install_gemfile <<-G
        source "https://gem.repo2"

        gem "myrack"
        gem "foo"
      G
      bundle_config "deployment true"
    end

    it "outputs a helpful message about being in deployment mode" do
      update_repo2 { build_gem "activesupport", "3.0" }

      bundle "outdated", raise_on_error: false
      expect(last_command).to be_failure
      expect(err).to include("You are trying to check outdated gems in deployment mode.")
      expect(err).to include("Run `bundle outdated` elsewhere.")
      expect(err).to include("If this is a development machine, remove the ")
      expect(err).to include("Gemfile freeze\nby running `bundle config unset deployment`.")
    end
  end

  context "update available for a gem on a different platform" do
    before do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "laduradura", '= 5.15.2'
      G
    end

    it "reports that no updates are available" do
      bundle "outdated"
      expect(out).to end_with("Bundle up to date!")
    end
  end

  context "update available for a gem on the same platform while multiple platforms used for gem" do
    before do
      build_repo2
    end

    it "reports that updates are available if the Ruby platform is used" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "laduradura", '= 5.15.2', :platforms => [:ruby, :jruby]
      G

      bundle "outdated"
      expect(out).to end_with("Bundle up to date!")
    end

    it "reports that updates are available if the JRuby platform is used", :jruby_only do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "laduradura", '= 5.15.2', :platforms => [:ruby, :jruby]
      G

      bundle "outdated", raise_on_error: false

      expected_output = <<~TABLE.strip
        Gem         Current  Latest  Requested  Groups   Release Date
        laduradura  5.15.2   5.15.3  = 5.15.2   default
      TABLE

      expect(out).to end_with(expected_output)
    end
  end

  shared_examples_for "version update is detected" do
    it "reports that a gem has a newer version" do
      subject

      outdated_gems = out.split("\n").drop_while {|l| !l.start_with?("Gem") }[1..-1]

      expect(outdated_gems.size).to be > 0
    end
  end

  shared_examples_for "major version updates are detected" do
    before do
      build_repo2 do
        build_git "foo", path: lib_path("foo")
        build_git "zebra", path: lib_path("zebra")
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G

      update_repo2 do
        build_gem "activesupport", "3.3.5"
        build_gem "weakling", "0.8.0"
      end
    end

    it_behaves_like "version update is detected"
  end

  context "when on a new machine" do
    before do
      build_repo2 do
        build_git "foo", path: lib_path("foo")
        build_git "zebra", path: lib_path("zebra")
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G

      pristine_system_gems

      update_git "foo", path: lib_path("foo")
      update_repo2 do
        build_gem "activesupport", "3.3.5"
        build_gem "weakling", "0.8.0"
      end
    end

    subject { bundle "outdated", raise_on_error: false }
    it_behaves_like "version update is detected"
  end

  shared_examples_for "minor version updates are detected" do
    before do
      build_repo2 do
        build_git "foo", path: lib_path("foo")
        build_git "zebra", path: lib_path("zebra")
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G

      update_repo2 do
        build_gem "activesupport", "2.7.5"
        build_gem "weakling", "2.0.1"
      end
    end

    it_behaves_like "version update is detected"
  end

  shared_examples_for "patch version updates are detected" do
    before do
      build_repo2 do
        build_git "foo", path: lib_path("foo")
        build_git "zebra", path: lib_path("zebra")
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G

      update_repo2 do
        build_gem "activesupport", "2.3.7"
        build_gem "weakling", "0.3.1"
      end
    end

    it_behaves_like "version update is detected"
  end

  shared_examples_for "no version updates are detected" do
    it "does not detect any version updates" do
      subject
      expect(out).to end_with("updates to display.")
    end
  end

  shared_examples_for "major version is ignored" do
    before do
      build_repo2 do
        build_git "foo", path: lib_path("foo")
        build_git "zebra", path: lib_path("zebra")
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G

      update_repo2 do
        build_gem "activesupport", "3.3.5"
        build_gem "weakling", "1.0.1"
      end
    end

    it_behaves_like "no version updates are detected"
  end

  shared_examples_for "minor version is ignored" do
    before do
      build_repo2 do
        build_git "foo", path: lib_path("foo")
        build_git "zebra", path: lib_path("zebra")
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G

      update_repo2 do
        build_gem "activesupport", "2.4.5"
        build_gem "weakling", "0.3.1"
      end
    end

    it_behaves_like "no version updates are detected"
  end

  shared_examples_for "patch version is ignored" do
    before do
      build_repo2 do
        build_git "foo", path: lib_path("foo")
        build_git "zebra", path: lib_path("zebra")
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G

      update_repo2 do
        build_gem "activesupport", "2.3.6"
        build_gem "weakling", "0.0.4"
      end
    end

    it_behaves_like "no version updates are detected"
  end

  describe "with --filter-major option" do
    subject { bundle "outdated --filter-major", raise_on_error: false }

    it_behaves_like "major version updates are detected"
    it_behaves_like "minor version is ignored"
    it_behaves_like "patch version is ignored"
  end

  describe "with --filter-minor option" do
    subject { bundle "outdated --filter-minor", raise_on_error: false }

    it_behaves_like "minor version updates are detected"
    it_behaves_like "major version is ignored"
    it_behaves_like "patch version is ignored"
  end

  describe "with --filter-patch option" do
    subject { bundle "outdated --filter-patch", raise_on_error: false }

    it_behaves_like "patch version updates are detected"
    it_behaves_like "major version is ignored"
    it_behaves_like "minor version is ignored"
  end

  describe "with --filter-minor --filter-patch options" do
    subject { bundle "outdated --filter-minor --filter-patch", raise_on_error: false }

    it_behaves_like "minor version updates are detected"
    it_behaves_like "patch version updates are detected"
    it_behaves_like "major version is ignored"
  end

  describe "with --filter-major --filter-minor options" do
    subject { bundle "outdated --filter-major --filter-minor", raise_on_error: false }

    it_behaves_like "major version updates are detected"
    it_behaves_like "minor version updates are detected"
    it_behaves_like "patch version is ignored"
  end

  describe "with --filter-major --filter-patch options" do
    subject { bundle "outdated --filter-major --filter-patch", raise_on_error: false }

    it_behaves_like "major version updates are detected"
    it_behaves_like "patch version updates are detected"
    it_behaves_like "minor version is ignored"
  end

  describe "with --filter-major --filter-minor --filter-patch options" do
    subject { bundle "outdated --filter-major --filter-minor --filter-patch", raise_on_error: false }

    it_behaves_like "major version updates are detected"
    it_behaves_like "minor version updates are detected"
    it_behaves_like "patch version updates are detected"
  end

  context "conservative updates" do
    before do
      build_repo4 do
        build_gem "patch", %w[1.0.0 1.0.1]
        build_gem "minor", %w[1.0.0 1.0.1 1.1.0]
        build_gem "major", %w[1.0.0 1.0.1 1.1.0 2.0.0]
      end

      # establish a lockfile set to 1.0.0
      install_gemfile <<-G
        source "https://gem.repo4"
        gem 'patch', '1.0.0'
        gem 'minor', '1.0.0'
        gem 'major', '1.0.0'
      G

      # remove all version requirements
      gemfile <<-G
        source "https://gem.repo4"
        gem 'patch'
        gem 'minor'
        gem 'major'
      G
    end

    it "shows nothing when patching and filtering to minor" do
      bundle "outdated --patch --filter-minor"

      expect(out).to end_with("No minor updates to display.")
    end

    it "shows all gems when patching and filtering to patch" do
      bundle "outdated --patch --filter-patch", raise_on_error: false

      expected_output = <<~TABLE.strip
        Gem    Current  Latest  Requested  Groups   Release Date
        major  1.0.0    1.0.1   >= 0       default
        minor  1.0.0    1.0.1   >= 0       default
        patch  1.0.0    1.0.1   >= 0       default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "shows minor and major when updating to minor and filtering to patch and minor" do
      bundle "outdated --minor --filter-minor", raise_on_error: false

      expected_output = <<~TABLE.strip
        Gem    Current  Latest  Requested  Groups   Release Date
        major  1.0.0    1.1.0   >= 0       default
        minor  1.0.0    1.1.0   >= 0       default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "shows minor when updating to major and filtering to minor with parseable" do
      bundle "outdated --major --filter-minor --parseable", raise_on_error: false

      expect(out).not_to include("patch (newest")
      expect(out).to include("minor (newest")
      expect(out).not_to include("major (newest")
    end
  end

  context "tricky conservative updates" do
    before do
      build_repo4 do
        build_gem "foo", %w[1.4.3 1.4.4] do |s|
          s.add_dependency "bar", "~> 2.0"
        end
        build_gem "foo", %w[1.4.5 1.5.0] do |s|
          s.add_dependency "bar", "~> 2.1"
        end
        build_gem "foo", %w[1.5.1] do |s|
          s.add_dependency "bar", "~> 3.0"
        end
        build_gem "bar", %w[2.0.3 2.0.4 2.0.5 2.1.0 2.1.1 3.0.0]
        build_gem "qux", %w[1.0.0 1.1.0 2.0.0]
      end

      # establish a lockfile set to 1.4.3
      install_gemfile <<-G
        source "https://gem.repo4"
        gem 'foo', '1.4.3'
        gem 'bar', '2.0.3'
        gem 'qux', '1.0.0'
      G

      # remove 1.4.3 requirement and bar altogether
      # to setup update specs below
      gemfile <<-G
        source "https://gem.repo4"
        gem 'foo'
        gem 'qux'
      G
    end

    it "shows gems updating to patch and filtering to patch" do
      bundle "outdated --patch --filter-patch", raise_on_error: false, env: { "DEBUG_RESOLVER" => "1" }

      expected_output = <<~TABLE.strip
        Gem  Current  Latest  Requested  Groups   Release Date
        bar  2.0.3    2.0.5
        foo  1.4.3    1.4.4   >= 0       default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "shows gems updating to patch and filtering to patch, in debug mode" do
      bundle "outdated --patch --filter-patch", raise_on_error: false, env: { "DEBUG" => "1" }

      expected_output = <<~TABLE.strip
        Gem  Current  Latest  Requested  Groups   Release Date  Path
        bar  2.0.3    2.0.5
        foo  1.4.3    1.4.4   >= 0       default
      TABLE

      expect(out).to end_with(expected_output)
    end
  end

  describe "with --only-explicit" do
    it "does not report outdated dependent gems" do
      build_repo4 do
        build_gem "weakling", %w[0.2 0.3] do |s|
          s.add_dependency "bar", "~> 2.1"
        end
        build_gem "bar", %w[2.1 2.2]
      end

      install_gemfile <<-G
        source "https://gem.repo4"
        gem 'weakling', '0.2'
        gem 'bar', '2.1'
      G

      gemfile  <<-G
        source "https://gem.repo4"
        gem 'weakling'
      G

      bundle "outdated --only-explicit", raise_on_error: false

      expected_output = <<~TABLE.strip
        Gem       Current  Latest  Requested  Groups   Release Date
        weakling  0.2      0.3     >= 0       default
      TABLE

      expect(out).to end_with(expected_output)
    end
  end

  describe "with a multiplatform lockfile" do
    before do
      build_repo4 do
        build_gem "nokogiri", "1.11.1"
        build_gem "nokogiri", "1.11.1" do |s|
          s.platform = Bundler.local_platform
        end

        build_gem "nokogiri", "1.11.2"
        build_gem "nokogiri", "1.11.2" do |s|
          s.platform = Bundler.local_platform
        end
      end

      lockfile <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            nokogiri (1.11.1)
            nokogiri (1.11.1-#{Bundler.local_platform})

        PLATFORMS
          ruby
          #{Bundler.local_platform}

        DEPENDENCIES
          nokogiri

        BUNDLED WITH
          #{Bundler::VERSION}
      L

      gemfile <<-G
        source "https://gem.repo4"
        gem "nokogiri"
      G
    end

    it "reports a single entry per gem" do
      bundle "outdated", raise_on_error: false

      expected_output = <<~TABLE.strip
        Gem       Current  Latest  Requested  Groups   Release Date
        nokogiri  1.11.1   1.11.2  >= 0       default
      TABLE

      expect(out).to end_with(expected_output)
    end
  end

  context "when a gem is no longer a dependency after a full update" do
    before do
      build_repo4 do
        build_gem "mini_portile2", "2.5.2" do |s|
          s.add_dependency "net-ftp", "~> 0.1"
        end

        build_gem "mini_portile2", "2.5.3"

        build_gem "net-ftp", "0.1.2"
      end

      gemfile <<~G
        source "https://gem.repo4"

        gem "mini_portile2"
      G

      lockfile <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            mini_portile2 (2.5.2)
              net-ftp (~> 0.1)
            net-ftp (0.1.2)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          mini_portile2

        BUNDLED WITH
          #{Bundler::VERSION}
      L
    end

    it "works" do
      bundle "outdated", raise_on_error: false

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups   Release Date
        mini_portile2  2.5.2    2.5.3   >= 0       default
      TABLE

      expect(out).to end_with(expected_output)
    end
  end
end
