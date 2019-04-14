# frozen_string_literal: true

RSpec.describe "bundle outdated" do
  before :each do
    build_repo2 do
      build_git "foo", :path => lib_path("foo")
      build_git "zebra", :path => lib_path("zebra")
    end

    install_gemfile <<-G
      source "file://#{gem_repo2}"
      gem "zebra", :git => "#{lib_path("zebra")}"
      gem "foo", :git => "#{lib_path("foo")}"
      gem "activesupport", "2.3.5"
      gem "weakling", "~> 0.0.1"
      gem "duradura", '7.0'
      gem "terranova", '8'
    G
  end

  describe "with no arguments" do
    it "returns a sorted list of outdated gems" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "weakling", "0.2"
        update_git "foo", :path => lib_path("foo")
        update_git "zebra", :path => lib_path("zebra")
      end

      bundle "outdated"

      expect(out).to include("activesupport (newest 3.0, installed 2.3.5, requested = 2.3.5)")
      expect(out).to include("weakling (newest 0.2, installed 0.0.3, requested ~> 0.0.1)")
      expect(out).to include("foo (newest 1.0")

      # Gem names are one per-line, between "*" and their parenthesized version.
      gem_list = out.split("\n").map {|g| g[/\* (.*) \(/, 1] }.compact
      expect(gem_list).to eq(gem_list.sort)
    end

    it "returns non zero exit status if outdated gems present" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        update_git "foo", :path => lib_path("foo")
      end

      bundle "outdated"

      expect(exitstatus).to_not be_zero if exitstatus
    end

    it "returns success exit status if no outdated gems present" do
      bundle "outdated"

      expect(exitstatus).to be_zero if exitstatus
    end

    it "adds gem group to dependency output when repo is updated" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"

        group :development, :test do
          gem 'activesupport', '2.3.5'
        end
      G

      update_repo2 { build_gem "activesupport", "3.0" }

      bundle "outdated --verbose"
      expect(out).to include("activesupport (newest 3.0, installed 2.3.5, requested = 2.3.5) in groups \"development, test\"")
    end
  end

  describe "with --group option" do
    def test_group_option(group = nil, gems_list_size = 1)
      install_gemfile <<-G
        source "file://#{gem_repo2}"

        gem "weakling", "~> 0.0.1"
        gem "terranova", '8'
        group :development, :test do
          gem "duradura", '7.0'
          gem 'activesupport', '2.3.5'
        end
      G

      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "terranova", "9"
        build_gem "duradura", "8.0"
      end

      bundle "outdated --group #{group}"

      # Gem names are one per-line, between "*" and their parenthesized version.
      gem_list = out.split("\n").map {|g| g[/\* (.*) \(/, 1] }.compact
      expect(gem_list).to eq(gem_list.sort)
      expect(gem_list.size).to eq gems_list_size
    end

    it "not outdated gems" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"

        gem "weakling", "~> 0.0.1"
        gem "terranova", '8'
        group :development, :test do
          gem 'activesupport', '2.3.5'
          gem "duradura", '7.0'
        end
      G

      bundle "outdated --group"
      expect(out).to include("Bundle up to date!")
    end

    it "returns a sorted list of outdated gems from one group => 'default'" do
      test_group_option("default")

      expect(out).to include("===== Group default =====")
      expect(out).to include("terranova (")

      expect(out).not_to include("===== Group development, test =====")
      expect(out).not_to include("activesupport")
      expect(out).not_to include("duradura")
    end

    it "returns a sorted list of outdated gems from one group => 'development'" do
      test_group_option("development", 2)

      expect(out).not_to include("===== Group default =====")
      expect(out).not_to include("terranova (")

      expect(out).to include("===== Group development, test =====")
      expect(out).to include("activesupport")
      expect(out).to include("duradura")
    end

    it "returns a sorted list of outdated gems from one group => 'test'" do
      test_group_option("test", 2)

      expect(out).not_to include("===== Group default =====")
      expect(out).not_to include("terranova (")

      expect(out).to include("===== Group development, test =====")
      expect(out).to include("activesupport")
      expect(out).to include("duradura")
    end
  end

  describe "with --groups option" do
    it "not outdated gems" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"

        gem "weakling", "~> 0.0.1"
        gem "terranova", '8'
        group :development, :test do
          gem 'activesupport', '2.3.5'
          gem "duradura", '7.0'
        end
      G

      bundle "outdated --groups"
      expect(out).to include("Bundle up to date!")
    end

    it "returns a sorted list of outdated gems by groups" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"

        gem "weakling", "~> 0.0.1"
        gem "terranova", '8'
        group :development, :test do
          gem 'activesupport', '2.3.5'
          gem "duradura", '7.0'
        end
      G

      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "terranova", "9"
        build_gem "duradura", "8.0"
      end

      bundle "outdated --groups"
      expect(out).to include("===== Group default =====")
      expect(out).to include("terranova (newest 9, installed 8, requested = 8)")
      expect(out).to include("===== Group development, test =====")
      expect(out).to include("activesupport (newest 3.0, installed 2.3.5, requested = 2.3.5)")
      expect(out).to include("duradura (newest 8.0, installed 7.0, requested = 7.0)")

      expect(out).not_to include("weakling (")

      # TODO: check gems order inside the group
    end
  end

  describe "with --local option" do
    it "uses local cache to return a list of outdated gems" do
      update_repo2 do
        build_gem "activesupport", "2.3.4"
      end

      bundle! "config set clean false"

      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "activesupport", "2.3.4"
      G

      bundle "outdated --local"

      expect(out).to include("activesupport (newest 2.3.5, installed 2.3.4, requested = 2.3.4)")
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
        update_repo2 do
          build_gem "activesupport", "3.0"
          build_gem "weakling", "0.2"
        end
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
        expect(out).to eq("")
      end
    end
  end

  describe "with --parseable option" do
    subject { bundle "outdated --parseable" }

    it_behaves_like "a minimal output is desired"
  end

  describe "with aliased --porcelain option" do
    subject { bundle "outdated --porcelain" }

    it_behaves_like "a minimal output is desired"
  end

  describe "with specified gems" do
    it "returns list of outdated gems" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        update_git "foo", :path => lib_path("foo")
      end

      bundle "outdated foo"
      expect(out).not_to include("activesupport (newest")
      expect(out).to include("foo (newest 1.0")
    end
  end

  describe "pre-release gems" do
    context "without the --pre option" do
      it "ignores pre-release versions" do
        update_repo2 do
          build_gem "activesupport", "3.0.0.beta"
        end

        bundle "outdated"
        expect(out).not_to include("activesupport (3.0.0.beta > 2.3.5)")
      end
    end

    context "with the --pre option" do
      it "includes pre-release versions" do
        update_repo2 do
          build_gem "activesupport", "3.0.0.beta"
        end

        bundle "outdated --pre"
        expect(out).to include("activesupport (newest 3.0.0.beta, installed 2.3.5, requested = 2.3.5)")
      end
    end

    context "when current gem is a pre-release" do
      it "includes the gem" do
        update_repo2 do
          build_gem "activesupport", "3.0.0.beta.1"
          build_gem "activesupport", "3.0.0.beta.2"
        end

        install_gemfile <<-G
          source "file://#{gem_repo2}"
          gem "activesupport", "3.0.0.beta.1"
        G

        bundle "outdated"
        expect(out).to include("(newest 3.0.0.beta.2, installed 3.0.0.beta.1, requested = 3.0.0.beta.1)")
      end
    end
  end

  filter_strict_option = Bundler.feature_flag.bundler_2_mode? ? :"filter-strict" : :strict
  describe "with --#{filter_strict_option} option" do
    it "only reports gems that have a newer version that matches the specified dependency version requirements" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        build_gem "weakling", "0.0.5"
      end

      bundle :outdated, filter_strict_option => true

      expect(out).to_not include("activesupport (newest")
      expect(out).to include("(newest 0.0.5, installed 0.0.3, requested ~> 0.0.1)")
    end

    it "only reports gem dependencies when they can actually be updated" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "rack_middleware", "1.0"
      G

      bundle :outdated, filter_strict_option => true

      expect(out).to_not include("rack (1.2")
    end

    describe "and filter options" do
      it "only reports gems that match requirement and patch filter level" do
        install_gemfile <<-G
          source "file://#{gem_repo2}"
          gem "activesupport", "~> 2.3"
          gem "weakling", ">= 0.0.1"
        G

        update_repo2 do
          build_gem "activesupport", %w[2.4.0 3.0.0]
          build_gem "weakling", "0.0.5"
        end

        bundle :outdated, filter_strict_option => true, "filter-patch" => true

        expect(out).to_not include("activesupport (newest")
        expect(out).to include("(newest 0.0.5, installed 0.0.3")
      end

      it "only reports gems that match requirement and minor filter level" do
        install_gemfile <<-G
          source "file://#{gem_repo2}"
          gem "activesupport", "~> 2.3"
          gem "weakling", ">= 0.0.1"
        G

        update_repo2 do
          build_gem "activesupport", %w[2.3.9]
          build_gem "weakling", "0.1.5"
        end

        bundle :outdated, filter_strict_option => true, "filter-minor" => true

        expect(out).to_not include("activesupport (newest")
        expect(out).to include("(newest 0.1.5, installed 0.0.3")
      end

      it "only reports gems that match requirement and major filter level" do
        install_gemfile <<-G
          source "file://#{gem_repo2}"
          gem "activesupport", "~> 2.3"
          gem "weakling", ">= 0.0.1"
        G

        update_repo2 do
          build_gem "activesupport", %w[2.4.0 2.5.0]
          build_gem "weakling", "1.1.5"
        end

        bundle :outdated, filter_strict_option => true, "filter-major" => true

        expect(out).to_not include("activesupport (newest")
        expect(out).to include("(newest 1.1.5, installed 0.0.3")
      end
    end
  end

  describe "with invalid gem name" do
    it "returns could not find gem name" do
      bundle "outdated invalid_gem_name"
      expect(err).to include("Could not find gem 'invalid_gem_name'.")
    end

    it "returns non-zero exit code" do
      bundle "outdated invalid_gem_name"
      expect(exitstatus).to_not be_zero if exitstatus
    end
  end

  it "performs an automatic bundle install" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack", "0.9.1"
      gem "foo"
    G

    bundle "config set auto_install 1"
    bundle :outdated
    expect(out).to include("Installing foo 1.0")
  end

  context "after bundle install --deployment", :bundler => "< 3" do
    before do
      install_gemfile <<-G, forgotten_command_line_options(:deployment => true)
        source "file://#{gem_repo2}"

        gem "rack"
        gem "foo"
      G
    end

    it "outputs a helpful message about being in deployment mode" do
      update_repo2 { build_gem "activesupport", "3.0" }

      bundle "outdated"
      expect(last_command).to be_failure
      expect(err).to include("You are trying to check outdated gems in deployment mode.")
      expect(err).to include("Run `bundle outdated` elsewhere.")
      expect(err).to include("If this is a development machine, remove the ")
      expect(err).to include("Gemfile freeze\nby running `bundle install --no-deployment`.")
    end
  end

  context "after bundle config set deployment true" do
    before do
      install_gemfile <<-G
        source "file://#{gem_repo2}"

        gem "rack"
        gem "foo"
      G
      bundle! "config set deployment true"
    end

    it "outputs a helpful message about being in deployment mode" do
      update_repo2 { build_gem "activesupport", "3.0" }

      bundle "outdated"
      expect(last_command).to be_failure
      expect(err).to include("You are trying to check outdated gems in deployment mode.")
      expect(err).to include("Run `bundle outdated` elsewhere.")
      expect(err).to include("If this is a development machine, remove the ")
      expect(err).to include("Gemfile freeze\nby running `bundle config unset deployment`.")
    end
  end

  context "update available for a gem on a different platform" do
    before do
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "laduradura", '= 5.15.2'
      G
    end

    it "reports that no updates are available" do
      bundle "outdated"
      expect(out).to include("Bundle up to date!")
    end
  end

  context "update available for a gem on the same platform while multiple platforms used for gem" do
    it "reports that updates are available if the Ruby platform is used" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "laduradura", '= 5.15.2', :platforms => [:ruby, :jruby]
      G

      bundle "outdated"
      expect(out).to include("Bundle up to date!")
    end

    it "reports that updates are available if the JRuby platform is used" do
      simulate_ruby_engine "jruby", "1.6.7" do
        simulate_platform "jruby" do
          install_gemfile <<-G
            source "file://#{gem_repo2}"
            gem "laduradura", '= 5.15.2', :platforms => [:ruby, :jruby]
          G

          bundle "outdated"
          expect(out).to include("Outdated gems included in the bundle:")
          expect(out).to include("laduradura (newest 5.15.3, installed 5.15.2, requested = 5.15.2)")
        end
      end
    end
  end

  shared_examples_for "version update is detected" do
    it "reports that a gem has a newer version" do
      subject
      expect(out).to include("Outdated gems included in the bundle:")
      expect(out).to include("activesupport (newest")
      expect(out).to_not include("ERROR REPORT TEMPLATE")
    end
  end

  shared_examples_for "major version updates are detected" do
    before do
      update_repo2 do
        build_gem "activesupport", "3.3.5"
        build_gem "weakling", "0.8.0"
      end
    end

    it_behaves_like "version update is detected"
  end

  context "when on a new machine" do
    before do
      simulate_new_machine

      update_git "foo", :path => lib_path("foo")
      update_repo2 do
        build_gem "activesupport", "3.3.5"
        build_gem "weakling", "0.8.0"
      end
    end

    subject { bundle "outdated" }
    it_behaves_like "version update is detected"
  end

  shared_examples_for "minor version updates are detected" do
    before do
      update_repo2 do
        build_gem "activesupport", "2.7.5"
        build_gem "weakling", "2.0.1"
      end
    end

    it_behaves_like "version update is detected"
  end

  shared_examples_for "patch version updates are detected" do
    before do
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
      expect(out).to include("updates to display.")
      expect(out).to_not include("ERROR REPORT TEMPLATE")
      expect(out).to_not include("activesupport (newest")
      expect(out).to_not include("weakling (newest")
    end
  end

  shared_examples_for "major version is ignored" do
    before do
      update_repo2 do
        build_gem "activesupport", "3.3.5"
        build_gem "weakling", "1.0.1"
      end
    end

    it_behaves_like "no version updates are detected"
  end

  shared_examples_for "minor version is ignored" do
    before do
      update_repo2 do
        build_gem "activesupport", "2.4.5"
        build_gem "weakling", "0.3.1"
      end
    end

    it_behaves_like "no version updates are detected"
  end

  shared_examples_for "patch version is ignored" do
    before do
      update_repo2 do
        build_gem "activesupport", "2.3.6"
        build_gem "weakling", "0.0.4"
      end
    end

    it_behaves_like "no version updates are detected"
  end

  describe "with --filter-major option" do
    subject { bundle "outdated --filter-major" }

    it_behaves_like "major version updates are detected"
    it_behaves_like "minor version is ignored"
    it_behaves_like "patch version is ignored"
  end

  describe "with --filter-minor option" do
    subject { bundle "outdated --filter-minor" }

    it_behaves_like "minor version updates are detected"
    it_behaves_like "major version is ignored"
    it_behaves_like "patch version is ignored"
  end

  describe "with --filter-patch option" do
    subject { bundle "outdated --filter-patch" }

    it_behaves_like "patch version updates are detected"
    it_behaves_like "major version is ignored"
    it_behaves_like "minor version is ignored"
  end

  describe "with --filter-minor --filter-patch options" do
    subject { bundle "outdated --filter-minor --filter-patch" }

    it_behaves_like "minor version updates are detected"
    it_behaves_like "patch version updates are detected"
    it_behaves_like "major version is ignored"
  end

  describe "with --filter-major --filter-minor options" do
    subject { bundle "outdated --filter-major --filter-minor" }

    it_behaves_like "major version updates are detected"
    it_behaves_like "minor version updates are detected"
    it_behaves_like "patch version is ignored"
  end

  describe "with --filter-major --filter-patch options" do
    subject { bundle "outdated --filter-major --filter-patch" }

    it_behaves_like "major version updates are detected"
    it_behaves_like "patch version updates are detected"
    it_behaves_like "minor version is ignored"
  end

  describe "with --filter-major --filter-minor --filter-patch options" do
    subject { bundle "outdated --filter-major --filter-minor --filter-patch" }

    it_behaves_like "major version updates are detected"
    it_behaves_like "minor version updates are detected"
    it_behaves_like "patch version updates are detected"
  end

  context "conservative updates" do
    context "without update-strict" do
      before do
        build_repo4 do
          build_gem "patch", %w[1.0.0 1.0.1]
          build_gem "minor", %w[1.0.0 1.0.1 1.1.0]
          build_gem "major", %w[1.0.0 1.0.1 1.1.0 2.0.0]
        end

        # establish a lockfile set to 1.0.0
        install_gemfile <<-G
        source "file://#{gem_repo4}"
        gem 'patch', '1.0.0'
        gem 'minor', '1.0.0'
        gem 'major', '1.0.0'
        G

        # remove 1.4.3 requirement and bar altogether
        # to setup update specs below
        gemfile <<-G
        source "file://#{gem_repo4}"
        gem 'patch'
        gem 'minor'
        gem 'major'
        G
      end

      it "shows nothing when patching and filtering to minor" do
        bundle "outdated --patch --filter-minor"

        expect(out).to include("No minor updates to display.")
        expect(out).not_to include("patch (newest")
        expect(out).not_to include("minor (newest")
        expect(out).not_to include("major (newest")
      end

      it "shows all gems when patching and filtering to patch" do
        bundle "outdated --patch --filter-patch"

        expect(out).to include("patch (newest 1.0.1")
        expect(out).to include("minor (newest 1.0.1")
        expect(out).to include("major (newest 1.0.1")
      end

      it "shows minor and major when updating to minor and filtering to patch and minor" do
        bundle "outdated --minor --filter-minor"

        expect(out).not_to include("patch (newest")
        expect(out).to include("minor (newest 1.1.0")
        expect(out).to include("major (newest 1.1.0")
      end

      it "shows minor when updating to major and filtering to minor with parseable" do
        bundle "outdated --major --filter-minor --parseable"

        expect(out).not_to include("patch (newest")
        expect(out).to include("minor (newest")
        expect(out).not_to include("major (newest")
      end
    end

    context "with update-strict" do
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
          source "file://#{gem_repo4}"
          gem 'foo', '1.4.3'
          gem 'bar', '2.0.3'
          gem 'qux', '1.0.0'
        G

        # remove 1.4.3 requirement and bar altogether
        # to setup update specs below
        gemfile <<-G
          source "file://#{gem_repo4}"
          gem 'foo'
          gem 'qux'
        G
      end

      it "shows gems with update-strict updating to patch and filtering to patch" do
        bundle "outdated --patch --update-strict --filter-patch"

        expect(out).to include("foo (newest 1.4.4")
        expect(out).to include("bar (newest 2.0.5")
        expect(out).not_to include("qux (newest")
      end
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
        source "file://#{gem_repo4}"
        gem 'weakling', '0.2'
        gem 'bar', '2.1'
      G

      gemfile  <<-G
        source "file://#{gem_repo4}"
        gem 'weakling'
      G

      bundle "outdated --only-explicit"

      expect(out).to include("weakling (newest 0.3")
      expect(out).not_to include("bar (newest 2.2")
    end
  end
end
