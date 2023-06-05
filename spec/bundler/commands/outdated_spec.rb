# frozen_string_literal: true

RSpec.describe "bundle outdated" do
  describe "with no arguments" do
    before do
      build_repo2 do
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G
    end

    it "returns a sorted list of outdated gems" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "weakling", "0.2"
        update_git "foo", :path => lib_path("foo")
        update_git "zebra", :path => lib_path("zebra")
      end

      bundle "outdated", :raise_on_error => false

      expected_output = <<~TABLE.gsub("x", "\\\h").tr(".", "\.").strip
        Gem            Current      Latest       Requested  Groups
        activesupport  2.3.5        3.0          = 2.3.5    default
        foo            1.0 xxxxxxx  1.0 xxxxxxx  >= 0       default
        weakling       0.0.3        0.2          ~> 0.0.1   default
        zebra          1.0 xxxxxxx  1.0 xxxxxxx  >= 0       default
      TABLE

      expect(out).to match(Regexp.new(expected_output))
    end

    it "excludes header row from the sorting" do
      update_repo2 do
        build_gem "AAA", %w[1.0.0 2.0.0]
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "AAA", "1.0.0"
      G

      bundle "outdated", :raise_on_error => false

      expected_output = <<~TABLE
        Gem  Current  Latest  Requested  Groups
        AAA  1.0.0    2.0.0   = 1.0.0    default
      TABLE

      expect(out).to include(expected_output.strip)
    end

    it "returns non zero exit status if outdated gems present" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        update_git "foo", :path => lib_path("foo")
      end

      bundle "outdated", :raise_on_error => false

      expect(exitstatus).to_not be_zero
    end

    it "returns success exit status if no outdated gems present" do
      bundle "outdated"
    end

    it "adds gem group to dependency output when repo is updated" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"

        gem "terranova", '8'

        group :development, :test do
          gem 'activesupport', '2.3.5'
        end
      G

      update_repo2 { build_gem "activesupport", "3.0" }
      update_repo2 { build_gem "terranova", "9" }

      bundle "outdated", :raise_on_error => false

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups
        activesupport  2.3.5    3.0     = 2.3.5    development, test
        terranova      8        9       = 8        default
      TABLE

      expect(out).to end_with(expected_output)
    end
  end

  describe "with --verbose option" do
    before do
      build_repo2 do
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G
    end

    it "shows the location of the latest version's gemspec if installed" do
      bundle "config set clean false"

      update_repo2 { build_gem "activesupport", "3.0" }
      update_repo2 { build_gem "terranova", "9" }

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"

        gem "terranova", '9'
        gem 'activesupport', '2.3.5'
      G

      gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"

        gem "terranova", '8'
        gem 'activesupport', '2.3.5'
      G

      bundle "outdated --verbose", :raise_on_error => false

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups   Path
        activesupport  2.3.5    3.0     = 2.3.5    default
        terranova      8        9       = 8        default  #{default_bundle_path("specifications/terranova-9.gemspec")}
      TABLE

      expect(out).to end_with(expected_output)
    end
  end

  describe "with multiple, duplicated sources, with lockfile in old format", :bundler => "< 3" do
    before do
      build_repo2 do
        build_gem "dotenv", "2.7.6"

        build_gem "oj", "3.11.3"
        build_gem "oj", "3.11.5"

        build_gem "vcr", "6.0.0"
      end

      build_repo gem_repo3 do
        build_gem "pkg-gem-flowbyte-with-dep", "1.0.0" do |s|
          s.add_dependency "oj"
        end
      end

      gemfile <<~G
        source "https://gem.repo2"

        gem "dotenv"

        source "https://gem.repo3" do
          gem 'pkg-gem-flowbyte-with-dep'
        end

        gem "vcr",source: "https://gem.repo2"
      G

      lockfile <<~L
        GEM
          remote: https://gem.repo2/
          remote: https://gem.repo3/
          specs:
            dotenv (2.7.6)
            oj (3.11.3)
            pkg-gem-flowbyte-with-dep (1.0.0)
              oj
            vcr (6.0.0)

        PLATFORMS
          #{local_platform}

        DEPENDENCIES
          dotenv
          pkg-gem-flowbyte-with-dep!
          vcr!

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end

    it "works" do
      bundle :install, :artifice => "compact_index"
      bundle :outdated, :artifice => "compact_index", :raise_on_error => false

      expected_output = <<~TABLE
        Gem  Current  Latest  Requested  Groups
        oj   3.11.3   3.11.5
      TABLE

      expect(out).to include(expected_output.strip)
    end
  end

  describe "with --group option" do
    before do
      build_repo2 do
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"

        gem "weakling", "~> 0.0.1"
        gem "terranova", '8'
        group :development, :test do
          gem "duradura", '7.0'
          gem 'activesupport', '2.3.5'
        end
      G
    end

    def test_group_option(group)
      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "terranova", "9"
        build_gem "duradura", "8.0"
      end

      bundle "outdated --group #{group}", :raise_on_error => false
    end

    it "works when the bundle is up to date" do
      bundle "outdated --group"
      expect(out).to end_with("Bundle up to date!")
    end

    it "returns a sorted list of outdated gems from one group => 'default'" do
      test_group_option("default")

      expected_output = <<~TABLE.strip
        Gem        Current  Latest  Requested  Groups
        terranova  8        9       = 8        default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "returns a sorted list of outdated gems from one group => 'development'" do
      test_group_option("development")

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups
        activesupport  2.3.5    3.0     = 2.3.5    development, test
        duradura       7.0      8.0     = 7.0      development, test
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "returns a sorted list of outdated gems from one group => 'test'" do
      test_group_option("test")

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups
        activesupport  2.3.5    3.0     = 2.3.5    development, test
        duradura       7.0      8.0     = 7.0      development, test
      TABLE

      expect(out).to end_with(expected_output)
    end
  end

  describe "with --groups option and outdated transitive dependencies" do
    before do
      build_repo2 do
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")

        build_gem "bar", %w[2.0.0]

        build_gem "bar_dependant", "7.0" do |s|
          s.add_dependency "bar", "~> 2.0"
        end
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"

        gem "bar_dependant", '7.0'
      G

      update_repo2 do
        build_gem "bar", %w[3.0.0]
      end
    end

    it "returns a sorted list of outdated gems" do
      bundle "outdated --groups", :raise_on_error => false

      expected_output = <<~TABLE.strip
        Gem  Current  Latest  Requested  Groups
        bar  2.0.0    3.0.0
      TABLE

      expect(out).to end_with(expected_output)
    end
  end

  describe "with --groups option" do
    before do
      build_repo2 do
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"

        gem "weakling", "~> 0.0.1"
        gem "terranova", '8'
        group :development, :test do
          gem 'activesupport', '2.3.5'
          gem "duradura", '7.0'
        end
      G
    end

    it "not outdated gems" do
      bundle "outdated --groups"
      expect(out).to end_with("Bundle up to date!")
    end

    it "returns a sorted list of outdated gems by groups" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "terranova", "9"
        build_gem "duradura", "8.0"
      end

      bundle "outdated --groups", :raise_on_error => false

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups
        activesupport  2.3.5    3.0     = 2.3.5    development, test
        duradura       7.0      8.0     = 7.0      development, test
        terranova      8        9       = 8        default
      TABLE

      expect(out).to end_with(expected_output)
    end
  end

  describe "with --local option" do
    before do
      build_repo2 do
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"

        gem "weakling", "~> 0.0.1"
        gem "terranova", '8'
        group :development, :test do
          gem 'activesupport', '2.3.5'
          gem "duradura", '7.0'
        end
      G
    end

    it "uses local cache to return a list of outdated gems" do
      update_repo2 do
        build_gem "activesupport", "2.3.4"
      end

      bundle "config set clean false"

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "activesupport", "2.3.4"
      G

      bundle "outdated --local", :raise_on_error => false

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups
        activesupport  2.3.4    2.3.5   = 2.3.4    default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "doesn't hit repo2" do
      FileUtils.rm_rf(gem_repo2)

      bundle "outdated --local"
      expect(out).not_to match(/Fetching (gem|version|dependency) metadata from/)
    end
  end

  shared_examples_for "a minimal output is desired" do
    context "and gems are outdated" do
      before do
        build_repo2 do
          build_git "foo", :path => lib_path("foo")
          build_git "zebra", :path => lib_path("zebra")

          build_gem "activesupport", "3.0"
          build_gem "weakling", "0.2"
        end

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "zebra", :git => "#{lib_path("zebra")}"
          gem "foo", :git => "#{lib_path("foo")}"
          gem "activesupport", "2.3.5"
          gem "weakling", "~> 0.0.1"
          gem "duradura", '7.0'
          gem "terranova", '8'
        G
      end

      it "outputs a sorted list of outdated gems with a more minimal format" do
        minimal_output = "activesupport (newest 3.0, installed 2.3.5, requested = 2.3.5)\n" \
                         "weakling (newest 0.2, installed 0.0.3, requested ~> 0.0.1)"
        subject
        expect(out).to eq(minimal_output)
      end
    end

    context "and no gems are outdated" do
      it "has empty output" do
        subject
        expect(out).to be_empty
      end
    end
  end

  describe "with --parseable option" do
    subject { bundle "outdated --parseable", :raise_on_error => false }

    it_behaves_like "a minimal output is desired"
  end

  describe "with aliased --porcelain option" do
    subject { bundle "outdated --porcelain", :raise_on_error => false }

    it_behaves_like "a minimal output is desired"
  end

  describe "with specified gems" do
    it "returns list of outdated gems" do
      build_repo2 do
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G

      update_repo2 do
        build_gem "activesupport", "3.0"
        update_git "foo", :path => lib_path("foo")
      end

      bundle "outdated foo", :raise_on_error => false

      expected_output = <<~TABLE.gsub("x", "\\\h").tr(".", "\.").strip
        Gem  Current      Latest       Requested  Groups
        foo  1.0 xxxxxxx  1.0 xxxxxxx  >= 0       default
      TABLE

      expect(out).to match(Regexp.new(expected_output))
    end
  end

  describe "pre-release gems" do
    before do
      build_repo2 do
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G
    end

    context "without the --pre option" do
      it "ignores pre-release versions" do
        update_repo2 do
          build_gem "activesupport", "3.0.0.beta"
        end

        bundle "outdated"

        expect(out).to end_with("Bundle up to date!")
      end
    end

    context "with the --pre option" do
      it "includes pre-release versions" do
        update_repo2 do
          build_gem "activesupport", "3.0.0.beta"
        end

        bundle "outdated --pre", :raise_on_error => false

        expected_output = <<~TABLE.strip
          Gem            Current  Latest      Requested  Groups
          activesupport  2.3.5    3.0.0.beta  = 2.3.5    default
        TABLE

        expect(out).to end_with(expected_output)
      end
    end

    context "when current gem is a pre-release" do
      it "includes the gem" do
        update_repo2 do
          build_gem "activesupport", "3.0.0.beta.1"
          build_gem "activesupport", "3.0.0.beta.2"
        end

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "activesupport", "3.0.0.beta.1"
        G

        bundle "outdated", :raise_on_error => false

        expected_output = <<~TABLE.strip
          Gem            Current       Latest        Requested       Groups
          activesupport  3.0.0.beta.1  3.0.0.beta.2  = 3.0.0.beta.1  default
        TABLE

        expect(out).to end_with(expected_output)
      end
    end
  end

  describe "with --filter-strict option" do
    before do
      build_repo2 do
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G
    end

    it "only reports gems that have a newer version that matches the specified dependency version requirements" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "weakling", "0.0.5"
      end

      bundle :outdated, :"filter-strict" => true, :raise_on_error => false

      expected_output = <<~TABLE.strip
        Gem       Current  Latest  Requested  Groups
        weakling  0.0.3    0.0.5   ~> 0.0.1   default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "only reports gems that have a newer version that matches the specified dependency version requirements, using --strict alias" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "weakling", "0.0.5"
      end

      bundle :outdated, :strict => true, :raise_on_error => false

      expected_output = <<~TABLE.strip
        Gem       Current  Latest  Requested  Groups
        weakling  0.0.3    0.0.5   ~> 0.0.1   default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "doesn't crash when some deps unused on the current platform" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "activesupport", platforms: [:ruby_22]
      G

      bundle :outdated, :"filter-strict" => true

      expect(out).to end_with("Bundle up to date!")
    end

    it "only reports gem dependencies when they can actually be updated" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack_middleware", "1.0"
      G

      bundle :outdated, :"filter-strict" => true

      expect(out).to end_with("Bundle up to date!")
    end

    describe "and filter options" do
      it "only reports gems that match requirement and patch filter level" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "activesupport", "~> 2.3"
          gem "weakling", ">= 0.0.1"
        G

        update_repo2 do
          build_gem "activesupport", %w[2.4.0 3.0.0]
          build_gem "weakling", "0.0.5"
        end

        bundle :outdated, :"filter-strict" => true, "filter-patch" => true, :raise_on_error => false

        expected_output = <<~TABLE.strip
          Gem       Current  Latest  Requested  Groups
          weakling  0.0.3    0.0.5   >= 0.0.1   default
        TABLE

        expect(out).to end_with(expected_output)
      end

      it "only reports gems that match requirement and minor filter level" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "activesupport", "~> 2.3"
          gem "weakling", ">= 0.0.1"
        G

        update_repo2 do
          build_gem "activesupport", %w[2.3.9]
          build_gem "weakling", "0.1.5"
        end

        bundle :outdated, :"filter-strict" => true, "filter-minor" => true, :raise_on_error => false

        expected_output = <<~TABLE.strip
          Gem       Current  Latest  Requested  Groups
          weakling  0.0.3    0.1.5   >= 0.0.1   default
        TABLE

        expect(out).to end_with(expected_output)
      end

      it "only reports gems that match requirement and major filter level" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "activesupport", "~> 2.3"
          gem "weakling", ">= 0.0.1"
        G

        update_repo2 do
          build_gem "activesupport", %w[2.4.0 2.5.0]
          build_gem "weakling", "1.1.5"
        end

        bundle :outdated, :"filter-strict" => true, "filter-major" => true, :raise_on_error => false

        expected_output = <<~TABLE.strip
          Gem       Current  Latest  Requested  Groups
          weakling  0.0.3    1.1.5   >= 0.0.1   default
        TABLE

        expect(out).to end_with(expected_output)
      end
    end
  end

  describe "with invalid gem name" do
    before do
      build_repo2 do
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G
    end

    it "returns could not find gem name" do
      bundle "outdated invalid_gem_name", :raise_on_error => false
      expect(err).to include("Could not find gem 'invalid_gem_name'.")
    end

    it "returns non-zero exit code" do
      bundle "outdated invalid_gem_name", :raise_on_error => false
      expect(exitstatus).to_not be_zero
    end
  end

  it "performs an automatic bundle install" do
    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack", "0.9.1"
      gem "foo"
    G

    bundle "config set auto_install 1"
    bundle :outdated, :raise_on_error => false
    expect(out).to include("Installing foo 1.0")
  end

  context "after bundle install --deployment", :bundler => "< 3" do
    before do
      build_repo2

      gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"

        gem "rack"
        gem "foo"
      G
      bundle :lock
      bundle :install, :deployment => true
    end

    it "outputs a helpful message about being in deployment mode" do
      update_repo2 { build_gem "activesupport", "3.0" }

      bundle "outdated", :raise_on_error => false
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
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"

        gem "rack"
        gem "foo"
      G
      bundle "config set --local deployment true"
    end

    it "outputs a helpful message about being in deployment mode" do
      update_repo2 { build_gem "activesupport", "3.0" }

      bundle "outdated", :raise_on_error => false
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
        source "#{file_uri_for(gem_repo2)}"
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
        source "#{file_uri_for(gem_repo2)}"
        gem "laduradura", '= 5.15.2', :platforms => [:ruby, :jruby]
      G

      bundle "outdated"
      expect(out).to end_with("Bundle up to date!")
    end

    it "reports that updates are available if the JRuby platform is used", :jruby_only do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "laduradura", '= 5.15.2', :platforms => [:ruby, :jruby]
      G

      bundle "outdated", :raise_on_error => false

      expected_output = <<~TABLE.strip
        Gem         Current  Latest  Requested  Groups
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
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
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
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "zebra", :git => "#{lib_path("zebra")}"
        gem "foo", :git => "#{lib_path("foo")}"
        gem "activesupport", "2.3.5"
        gem "weakling", "~> 0.0.1"
        gem "duradura", '7.0'
        gem "terranova", '8'
      G

      simulate_new_machine

      update_git "foo", :path => lib_path("foo")
      update_repo2 do
        build_gem "activesupport", "3.3.5"
        build_gem "weakling", "0.8.0"
      end
    end

    subject { bundle "outdated", :raise_on_error => false }
    it_behaves_like "version update is detected"
  end

  shared_examples_for "minor version updates are detected" do
    before do
      build_repo2 do
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
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
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
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
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
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
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
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
        build_git "foo", :path => lib_path("foo")
        build_git "zebra", :path => lib_path("zebra")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
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
    subject { bundle "outdated --filter-major", :raise_on_error => false }

    it_behaves_like "major version updates are detected"
    it_behaves_like "minor version is ignored"
    it_behaves_like "patch version is ignored"
  end

  describe "with --filter-minor option" do
    subject { bundle "outdated --filter-minor", :raise_on_error => false }

    it_behaves_like "minor version updates are detected"
    it_behaves_like "major version is ignored"
    it_behaves_like "patch version is ignored"
  end

  describe "with --filter-patch option" do
    subject { bundle "outdated --filter-patch", :raise_on_error => false }

    it_behaves_like "patch version updates are detected"
    it_behaves_like "major version is ignored"
    it_behaves_like "minor version is ignored"
  end

  describe "with --filter-minor --filter-patch options" do
    subject { bundle "outdated --filter-minor --filter-patch", :raise_on_error => false }

    it_behaves_like "minor version updates are detected"
    it_behaves_like "patch version updates are detected"
    it_behaves_like "major version is ignored"
  end

  describe "with --filter-major --filter-minor options" do
    subject { bundle "outdated --filter-major --filter-minor", :raise_on_error => false }

    it_behaves_like "major version updates are detected"
    it_behaves_like "minor version updates are detected"
    it_behaves_like "patch version is ignored"
  end

  describe "with --filter-major --filter-patch options" do
    subject { bundle "outdated --filter-major --filter-patch", :raise_on_error => false }

    it_behaves_like "major version updates are detected"
    it_behaves_like "patch version updates are detected"
    it_behaves_like "minor version is ignored"
  end

  describe "with --filter-major --filter-minor --filter-patch options" do
    subject { bundle "outdated --filter-major --filter-minor --filter-patch", :raise_on_error => false }

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
        source "#{file_uri_for(gem_repo4)}"
        gem 'patch', '1.0.0'
        gem 'minor', '1.0.0'
        gem 'major', '1.0.0'
      G

      # remove all version requirements
      gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
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
      bundle "outdated --patch --filter-patch", :raise_on_error => false

      expected_output = <<~TABLE.strip
        Gem    Current  Latest  Requested  Groups
        major  1.0.0    1.0.1   >= 0       default
        minor  1.0.0    1.0.1   >= 0       default
        patch  1.0.0    1.0.1   >= 0       default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "shows minor and major when updating to minor and filtering to patch and minor" do
      bundle "outdated --minor --filter-minor", :raise_on_error => false

      expected_output = <<~TABLE.strip
        Gem    Current  Latest  Requested  Groups
        major  1.0.0    1.1.0   >= 0       default
        minor  1.0.0    1.1.0   >= 0       default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "shows minor when updating to major and filtering to minor with parseable" do
      bundle "outdated --major --filter-minor --parseable", :raise_on_error => false

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
        source "#{file_uri_for(gem_repo4)}"
        gem 'foo', '1.4.3'
        gem 'bar', '2.0.3'
        gem 'qux', '1.0.0'
      G

      # remove 1.4.3 requirement and bar altogether
      # to setup update specs below
      gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
        gem 'foo'
        gem 'qux'
      G
    end

    it "shows gems updating to patch and filtering to patch" do
      bundle "outdated --patch --filter-patch", :raise_on_error => false, :env => { "DEBUG_RESOLVER" => "1" }

      expected_output = <<~TABLE.strip
        Gem  Current  Latest  Requested  Groups
        bar  2.0.3    2.0.5
        foo  1.4.3    1.4.4   >= 0       default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "shows gems updating to patch and filtering to patch, in debug mode" do
      bundle "outdated --patch --filter-patch", :raise_on_error => false, :env => { "DEBUG" => "1" }

      expected_output = <<~TABLE.strip
        Gem  Current  Latest  Requested  Groups   Path
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
        source "#{file_uri_for(gem_repo4)}"
        gem 'weakling', '0.2'
        gem 'bar', '2.1'
      G

      gemfile  <<-G
        source "#{file_uri_for(gem_repo4)}"
        gem 'weakling'
      G

      bundle "outdated --only-explicit", :raise_on_error => false

      expected_output = <<~TABLE.strip
        Gem       Current  Latest  Requested  Groups
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
          remote: #{file_uri_for(gem_repo4)}/
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
        source "#{file_uri_for(gem_repo4)}"
        gem "nokogiri"
      G
    end

    it "reports a single entry per gem" do
      bundle "outdated", :raise_on_error => false

      expected_output = <<~TABLE.strip
        Gem       Current  Latest  Requested  Groups
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
        source "#{file_uri_for(gem_repo4)}"

        gem "mini_portile2"
      G

      lockfile <<~L
        GEM
          remote: #{file_uri_for(gem_repo4)}/
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
      bundle "outdated", :raise_on_error => false

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups
        mini_portile2  2.5.2    2.5.3   >= 0       default
      TABLE

      expect(out).to end_with(expected_output)
    end
  end
end
