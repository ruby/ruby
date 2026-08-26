# frozen_string_literal: true

RSpec.describe "bundle outdated" do
  describe "with no arguments" do
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
    end

    it "returns a sorted list of outdated gems" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "weakling", "0.2"
        update_git "foo", path: lib_path("foo")
        update_git "zebra", path: lib_path("zebra")
      end

      bundle "outdated", raise_on_error: false

      expected_output = <<~TABLE.gsub("x", "\\\h").tr(".", "\.").strip
        Gem            Current      Latest       Requested  Groups   Release Date
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
        source "https://gem.repo2"
        gem "AAA", "1.0.0"
      G

      bundle "outdated", raise_on_error: false

      expected_output = <<~TABLE
        Gem  Current  Latest  Requested  Groups   Release Date
        AAA  1.0.0    2.0.0   = 1.0.0    default
      TABLE

      expect(out).to include(expected_output.strip)
    end

    it "returns non zero exit status if outdated gems present" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        update_git "foo", path: lib_path("foo")
      end

      bundle "outdated", raise_on_error: false

      expect(exitstatus).to_not be_zero
    end

    it "returns success exit status if no outdated gems present" do
      bundle "outdated"
    end

    it "adds gem group to dependency output when repo is updated" do
      install_gemfile <<-G
        source "https://gem.repo2"

        gem "terranova", '8'

        group :development, :test do
          gem 'activesupport', '2.3.5'
        end
      G

      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "terranova", "9"
      end

      bundle "outdated", raise_on_error: false

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups             Release Date
        activesupport  2.3.5    3.0     = 2.3.5    development, test
        terranova      8        9       = 8        default
      TABLE

      expect(out).to end_with(expected_output)
    end
  end

  describe "with --verbose option" do
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
    end

    it "shows the location of the latest version's gemspec if installed" do
      bundle_config "clean false"

      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "terranova", "9"
      end

      install_gemfile <<-G
        source "https://gem.repo2"

        gem "terranova", '9'
        gem 'activesupport', '2.3.5'
      G

      gemfile <<-G
        source "https://gem.repo2"

        gem "terranova", '8'
        gem 'activesupport', '2.3.5'
      G

      bundle "outdated --verbose", raise_on_error: false

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups   Release Date  Path
        activesupport  2.3.5    3.0     = 2.3.5    default
        terranova      8        9       = 8        default                #{default_bundle_path("specifications/terranova-9.gemspec")}
      TABLE

      expect(out).to end_with(expected_output)
    end
  end

  describe "with --group option" do
    before do
      build_repo2 do
        build_git "foo", path: lib_path("foo")
        build_git "zebra", path: lib_path("zebra")
      end

      install_gemfile <<-G
        source "https://gem.repo2"

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

      bundle "outdated --group #{group}", raise_on_error: false
    end

    it "works when the bundle is up to date" do
      bundle "outdated --group"
      expect(out).to end_with("Bundle up to date!")
    end

    it "works when only out of date gems are not in given group" do
      update_repo2 do
        build_gem "terranova", "9"
      end
      bundle "outdated --group development"
      expect(out).to end_with("Bundle up to date!")
    end

    it "returns a sorted list of outdated gems from one group => 'default'" do
      test_group_option("default")

      expected_output = <<~TABLE.strip
        Gem        Current  Latest  Requested  Groups   Release Date
        terranova  8        9       = 8        default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "returns a sorted list of outdated gems from one group => 'development'" do
      test_group_option("development")

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups             Release Date
        activesupport  2.3.5    3.0     = 2.3.5    development, test
        duradura       7.0      8.0     = 7.0      development, test
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "returns a sorted list of outdated gems from one group => 'test'" do
      test_group_option("test")

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups             Release Date
        activesupport  2.3.5    3.0     = 2.3.5    development, test
        duradura       7.0      8.0     = 7.0      development, test
      TABLE

      expect(out).to end_with(expected_output)
    end
  end

  describe "with --groups option and outdated transitive dependencies" do
    before do
      build_repo2 do
        build_git "foo", path: lib_path("foo")
        build_git "zebra", path: lib_path("zebra")

        build_gem "bar", %w[2.0.0]

        build_gem "bar_dependant", "7.0" do |s|
          s.add_dependency "bar", "~> 2.0"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"

        gem "bar_dependant", '7.0'
      G

      update_repo2 do
        build_gem "bar", %w[3.0.0]
      end
    end

    it "returns a sorted list of outdated gems" do
      bundle "outdated --groups", raise_on_error: false

      expected_output = <<~TABLE.strip
        Gem  Current  Latest  Requested  Groups  Release Date
        bar  2.0.0    3.0.0
      TABLE

      expect(out).to end_with(expected_output)
    end
  end

  describe "with --groups option" do
    before do
      build_repo2 do
        build_git "foo", path: lib_path("foo")
        build_git "zebra", path: lib_path("zebra")
      end

      install_gemfile <<-G
        source "https://gem.repo2"

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

      bundle "outdated --groups", raise_on_error: false

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups             Release Date
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
        build_git "foo", path: lib_path("foo")
        build_git "zebra", path: lib_path("zebra")
      end

      install_gemfile <<-G
        source "https://gem.repo2"

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

      bundle_config "clean false"

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport", "2.3.4"
      G

      bundle "outdated --local", raise_on_error: false

      expected_output = <<~TABLE.strip
        Gem            Current  Latest  Requested  Groups   Release Date
        activesupport  2.3.4    2.3.5   = 2.3.4    default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "doesn't hit repo2" do
      FileUtils.rm_r(gem_repo2)

      bundle "outdated --local"
      expect(out).not_to match(/Fetching (gem|version|dependency) metadata from/)
    end
  end

  shared_examples_for "a minimal output is desired" do
    context "and gems are outdated" do
      before do
        build_repo2 do
          build_git "foo", path: lib_path("foo")
          build_git "zebra", path: lib_path("zebra")

          build_gem "activesupport", "3.0"
          build_gem "weakling", "0.2"
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
      end

      it "outputs a sorted list of outdated gems with a more minimal format to stdout" do
        minimal_output = "activesupport (newest 3.0, installed 2.3.5, requested = 2.3.5)\n" \
                         "weakling (newest 0.2, installed 0.0.3, requested ~> 0.0.1)"
        subject
        expect(out).to eq(minimal_output)
      end

      it "outputs progress to stderr" do
        subject
        expect(err).to include("Fetching gem metadata")
      end
    end

    context "and no gems are outdated" do
      before do
        build_repo2 do
          build_gem "activesupport", "3.0"
        end

        install_gemfile <<-G
          source "https://gem.repo2"
          gem "activesupport", "3.0"
        G
      end

      it "does not output to stdout" do
        subject
        expect(out).to be_empty
      end

      it "outputs progress to stderr" do
        subject
        expect(err).to include("Fetching gem metadata")
      end
    end
  end

  describe "with --parseable option" do
    subject { bundle "outdated --parseable", raise_on_error: false }

    it_behaves_like "a minimal output is desired"
  end

  describe "with aliased --porcelain option" do
    subject { bundle "outdated --porcelain", raise_on_error: false }

    it_behaves_like "a minimal output is desired"
  end

  describe "with specified gems" do
    it "returns list of outdated gems" do
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
        build_gem "activesupport", "3.0"
        update_git "foo", path: lib_path("foo")
      end

      bundle "outdated foo", raise_on_error: false

      expected_output = <<~TABLE.gsub("x", "\\\h").tr(".", "\.").strip
        Gem  Current      Latest       Requested  Groups   Release Date
        foo  1.0 xxxxxxx  1.0 xxxxxxx  >= 0       default
      TABLE

      expect(out).to match(Regexp.new(expected_output))
    end

    it "does not require gems to be installed" do
      build_repo4 do
        build_gem "zeitwerk", "1.0.0"
        build_gem "zeitwerk", "2.0.0"
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem "zeitwerk"
      G

      lockfile <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            zeitwerk (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          zeitwerk

        BUNDLED WITH
          #{Bundler::VERSION}
      L

      bundle "outdated zeitwerk", raise_on_error: false

      expected_output = <<~TABLE.tr(".", "\.").strip
        Gem       Current  Latest  Requested  Groups   Release Date
        zeitwerk  1.0.0    2.0.0   >= 0       default
      TABLE

      expect(out).to match(Regexp.new(expected_output))
      expect(err).to be_empty
    end
  end

  describe "pre-release gems" do
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

        bundle "outdated --pre", raise_on_error: false

        expected_output = <<~TABLE.strip
          Gem            Current  Latest      Requested  Groups   Release Date
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
          source "https://gem.repo2"
          gem "activesupport", "3.0.0.beta.1"
        G

        bundle "outdated", raise_on_error: false

        expected_output = <<~TABLE.strip
          Gem            Current       Latest        Requested       Groups   Release Date
          activesupport  3.0.0.beta.1  3.0.0.beta.2  = 3.0.0.beta.1  default
        TABLE

        expect(out).to end_with(expected_output)
      end
    end
  end

  describe "with --filter-strict option" do
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
    end

    it "only reports gems that have a newer version that matches the specified dependency version requirements" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "weakling", "0.0.5"
      end

      bundle :outdated, "filter-strict": true, raise_on_error: false

      expected_output = <<~TABLE.strip
        Gem       Current  Latest  Requested  Groups   Release Date
        weakling  0.0.3    0.0.5   ~> 0.0.1   default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "only reports gems that have a newer version that matches the specified dependency version requirements, using --strict alias" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "weakling", "0.0.5"
      end

      bundle :outdated, strict: true, raise_on_error: false

      expected_output = <<~TABLE.strip
        Gem       Current  Latest  Requested  Groups   Release Date
        weakling  0.0.3    0.0.5   ~> 0.0.1   default
      TABLE

      expect(out).to end_with(expected_output)
    end

    it "doesn't crash when some deps unused on the current platform" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport", platforms: [:ruby_22]
      G

      bundle :outdated, "filter-strict": true

      expect(out).to end_with("Bundle up to date!")
    end

    it "only reports gem dependencies when they can actually be updated" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack_middleware", "1.0"
      G

      bundle :outdated, "filter-strict": true

      expect(out).to end_with("Bundle up to date!")
    end

    describe "and filter options" do
      it "only reports gems that match requirement and patch filter level" do
        install_gemfile <<-G
          source "https://gem.repo2"
          gem "activesupport", "~> 2.3"
          gem "weakling", ">= 0.0.1"
        G

        update_repo2 do
          build_gem "activesupport", %w[2.4.0 3.0.0]
          build_gem "weakling", "0.0.5"
        end

        bundle :outdated, :"filter-strict" => true, "filter-patch" => true, :raise_on_error => false

        expected_output = <<~TABLE.strip
          Gem       Current  Latest  Requested  Groups   Release Date
          weakling  0.0.3    0.0.5   >= 0.0.1   default
        TABLE

        expect(out).to end_with(expected_output)
      end

      it "only reports gems that match requirement and minor filter level" do
        install_gemfile <<-G
          source "https://gem.repo2"
          gem "activesupport", "~> 2.3"
          gem "weakling", ">= 0.0.1"
        G

        update_repo2 do
          build_gem "activesupport", %w[2.3.9]
          build_gem "weakling", "0.1.5"
        end

        bundle :outdated, :"filter-strict" => true, "filter-minor" => true, :raise_on_error => false

        expected_output = <<~TABLE.strip
          Gem       Current  Latest  Requested  Groups   Release Date
          weakling  0.0.3    0.1.5   >= 0.0.1   default
        TABLE

        expect(out).to end_with(expected_output)
      end

      it "only reports gems that match requirement and major filter level" do
        install_gemfile <<-G
          source "https://gem.repo2"
          gem "activesupport", "~> 2.3"
          gem "weakling", ">= 0.0.1"
        G

        update_repo2 do
          build_gem "activesupport", %w[2.4.0 2.5.0]
          build_gem "weakling", "1.1.5"
        end

        bundle :outdated, :"filter-strict" => true, "filter-major" => true, :raise_on_error => false

        expected_output = <<~TABLE.strip
          Gem       Current  Latest  Requested  Groups   Release Date
          weakling  0.0.3    1.1.5   >= 0.0.1   default
        TABLE

        expect(out).to end_with(expected_output)
      end
    end
  end

  describe "with invalid gem name" do
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
    end

    it "returns could not find gem name" do
      bundle "outdated invalid_gem_name", raise_on_error: false
      expect(err).to include("Could not find gem 'invalid_gem_name'.")
    end

    it "returns non-zero exit code" do
      bundle "outdated invalid_gem_name", raise_on_error: false
      expect(exitstatus).to_not be_zero
    end
  end
end
