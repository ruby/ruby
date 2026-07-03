# frozen_string_literal: true

RSpec.describe "bundle update" do
  describe "with no arguments" do
    before do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport"
        gem "myrack-obama"
        gem "platform_specific"
      G
    end

    it "updates the entire bundle" do
      update_repo2 do
        build_gem "myrack", "1.2" do |s|
          s.executables = "myrackup"
        end

        build_gem "activesupport", "3.0"
      end

      bundle "update"
      expect(out).to include("Bundle updated!")
      expect(the_bundle).to include_gems "myrack 1.2", "myrack-obama 1.0", "activesupport 3.0"
    end

    it "doesn't delete the Gemfile.lock file if something goes wrong" do
      gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport"
        gem "myrack-obama"
        exit!
      G
      bundle "update", raise_on_error: false
      expect(bundled_app_lock).to exist
    end
  end

  describe "with --verbose" do
    before do
      build_repo2

      install_gemfile <<~G
        source "https://gem.repo2"
        gem "myrack"
      G
    end

    it "logs the reason for re-resolving" do
      bundle "update --verbose"
      expect(out).not_to include("Found changes from the lockfile")
      expect(out).to include("Re-resolving dependencies because bundler is unlocking")
    end
  end

  describe "with --all" do
    before do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport"
        gem "myrack-obama"
        gem "platform_specific"
      G
    end

    it "updates the entire bundle" do
      update_repo2 do
        build_gem "myrack", "1.2" do |s|
          s.executables = "myrackup"
        end

        build_gem "activesupport", "3.0"
      end

      bundle "update", all: true
      expect(out).to include("Bundle updated!")
      expect(the_bundle).to include_gems "myrack 1.2", "myrack-obama 1.0", "activesupport 3.0"
    end

    it "doesn't delete the Gemfile.lock file if something goes wrong" do
      install_gemfile "source 'https://gem.repo1'"

      gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport"
        gem "myrack-obama"
        exit!
      G
      bundle "update", all: true, raise_on_error: false
      expect(bundled_app_lock).to exist
    end
  end

  describe "with --gemfile" do
    it "creates lockfiles based on the Gemfile name" do
      gemfile bundled_app("OmgFile"), <<-G
        source "https://gem.repo1"
        gem "myrack", "1.0"
      G

      bundle "update --gemfile OmgFile", all: true

      expect(bundled_app("OmgFile.lock")).to exist
    end
  end

  context "when update_requires_all_flag is set" do
    before { bundle_config "update_requires_all_flag true" }

    it "errors when passed nothing" do
      install_gemfile "source 'https://gem.repo1'"
      bundle :update, raise_on_error: false
      expect(err).to eq("To update everything, pass the `--all` flag.")
    end

    it "errors when passed --all and another option" do
      install_gemfile "source 'https://gem.repo1'"
      bundle "update --all foo", raise_on_error: false
      expect(err).to eq("Cannot specify --all along with specific options.")
    end

    it "updates everything when passed --all" do
      install_gemfile "source 'https://gem.repo1'"
      bundle "update --all"
      expect(out).to include("Bundle updated!")
    end
  end

  describe "--quiet argument" do
    before do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport"
        gem "myrack-obama"
        gem "platform_specific"
      G
    end

    it "hides UI messages" do
      bundle "update --quiet"
      expect(out).not_to include("Bundle updated!")
    end
  end

  describe "with a top level dependency" do
    before do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport"
        gem "myrack-obama"
        gem "platform_specific"
      G
    end

    it "unlocks all child dependencies that are unrelated to other locked dependencies" do
      update_repo2 do
        build_gem "myrack", "1.2" do |s|
          s.executables = "myrackup"
        end

        build_gem "activesupport", "3.0"
      end

      bundle "update myrack-obama"
      expect(the_bundle).to include_gems "myrack 1.2", "myrack-obama 1.0", "activesupport 2.3.5"
    end
  end

  describe "with an unknown dependency" do
    before do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport"
        gem "myrack-obama"
        gem "platform_specific"
      G
    end

    it "should inform the user" do
      bundle "update halting-problem-solver", raise_on_error: false
      expect(err).to include "Could not find gem 'halting-problem-solver'"
    end
    it "should suggest alternatives" do
      bundle "update platformspecific", raise_on_error: false
      expect(err).to include "Did you mean 'platform_specific'?"
    end
  end

  describe "with a child dependency" do
    before do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport"
        gem "myrack-obama"
        gem "platform_specific"
      G
    end

    it "should update the child dependency" do
      update_repo2 do
        build_gem "myrack", "1.2" do |s|
          s.executables = "myrackup"
        end
      end

      bundle "update myrack"
      expect(the_bundle).to include_gems "myrack 1.2"
    end
  end

  describe "when a possible resolve requires an older version of a locked gem" do
    it "does not go to an older version" do
      build_repo4 do
        build_gem "tilt", "2.0.8"
        build_gem "slim", "3.0.9" do |s|
          s.add_dependency "tilt", [">= 1.3.3", "< 2.1"]
        end
        build_gem "slim_lint", "0.16.1" do |s|
          s.add_dependency "slim", [">= 3.0", "< 5.0"]
        end
        build_gem "slim-rails", "0.2.1" do |s|
          s.add_dependency "slim", ">= 0.9.2"
        end
        build_gem "slim-rails", "3.1.3" do |s|
          s.add_dependency "slim", "~> 3.0"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo4"
        gem "slim-rails"
        gem "slim_lint"
      G

      expect(the_bundle).to include_gems("slim 3.0.9", "slim-rails 3.1.3", "slim_lint 0.16.1")

      build_repo4 do
        build_gem "slim", "4.0.0" do |s|
          s.add_dependency "tilt", [">= 2.0.6", "< 2.1"]
        end
      end

      bundle "update", all: true

      expect(the_bundle).to include_gems("slim 3.0.9", "slim-rails 3.1.3", "slim_lint 0.16.1")
    end

    it "does not go to an older version, even if the version upgrade that could cause another gem to downgrade is activated first" do
      build_repo4 do
        # countries is processed before country_select by the resolver due to having less spec groups (groups of versions with the same dependencies) (2 vs 3)

        build_gem "countries", "2.1.4"
        build_gem "countries", "3.1.0"

        build_gem "countries", "4.0.0" do |s|
          s.add_dependency "sixarm_ruby_unaccent", "~> 1.1"
        end

        build_gem "country_select", "1.2.0"

        build_gem "country_select", "2.1.4" do |s|
          s.add_dependency "countries", "~> 2.0"
        end
        build_gem "country_select", "3.1.1" do |s|
          s.add_dependency "countries", "~> 2.0"
        end

        build_gem "country_select", "5.1.0" do |s|
          s.add_dependency "countries", "~> 3.0"
        end

        build_gem "sixarm_ruby_unaccent", "1.1.0"
      end

      gemfile <<~G
        source "https://gem.repo4"

        gem "country_select"
        gem "countries"
      G

      checksums = checksums_section_when_enabled do |c|
        c.checksum(gem_repo4, "countries", "3.1.0")
        c.checksum(gem_repo4, "country_select", "5.1.0")
      end

      lockfile <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            countries (3.1.0)
            country_select (5.1.0)
              countries (~> 3.0)

        PLATFORMS
          #{local_platform}

        DEPENDENCIES
          countries
          country_select
        #{checksums}
        BUNDLED WITH
          #{Bundler::VERSION}
      L

      previous_lockfile = lockfile

      bundle "lock --update", env: { "DEBUG" => "1" }, verbose: true

      expect(lockfile).to eq(previous_lockfile)
    end

    it "does not downgrade direct dependencies when run with --conservative" do
      build_repo4 do
        build_gem "oauth2", "2.0.6" do |s|
          s.add_dependency "faraday", ">= 0.17.3", "< 3.0"
        end

        build_gem "oauth2", "1.4.10" do |s|
          s.add_dependency "faraday", ">= 0.17.3", "< 3.0"
          s.add_dependency "multi_json", "~> 1.3"
        end

        build_gem "faraday", "2.5.2"

        build_gem "multi_json", "1.15.0"

        build_gem "quickbooks-ruby", "1.0.19" do |s|
          s.add_dependency "oauth2", "~> 1.4"
        end

        build_gem "quickbooks-ruby", "0.1.9" do |s|
          s.add_dependency "oauth2"
        end
      end

      gemfile <<-G
        source "https://gem.repo4"

        gem "oauth2"
        gem "quickbooks-ruby"
      G

      lockfile <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            faraday (2.5.2)
            multi_json (1.15.0)
            oauth2 (1.4.10)
              faraday (>= 0.17.3, < 3.0)
              multi_json (~> 1.3)
            quickbooks-ruby (1.0.19)
              oauth2 (~> 1.4)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          oauth2
          quickbooks-ruby

        BUNDLED WITH
          #{Bundler::VERSION}
      L

      bundle "update --conservative --verbose"

      expect(out).not_to include("Installing quickbooks-ruby 0.1.9")
      expect(out).to include("Installing quickbooks-ruby 1.0.19").and include("Installing oauth2 1.4.10")
    end

    it "does not downgrade direct dependencies when using gemspec sources" do
      create_file("rails.gemspec", <<-G)
        Gem::Specification.new do |gem|
          gem.name = "rails"
          gem.version = "7.1.0.alpha"
          gem.author = "DHH"
          gem.summary = "Full-stack web application framework."
        end
      G

      build_repo4 do
        build_gem "rake", "12.3.3"
        build_gem "rake", "13.0.6"

        build_gem "sneakers", "2.11.0" do |s|
          s.add_dependency "rake"
        end

        build_gem "sneakers", "2.12.0" do |s|
          s.add_dependency "rake", "~> 12.3"
        end
      end

      gemfile <<-G
        source "https://gem.repo4"

        gemspec

        gem "rake"
        gem "sneakers"
      G

      lockfile <<~L
        PATH
          remote: .
          specs:

        GEM
          remote: https://gem.repo4/
          specs:
            rake (13.0.6)
            sneakers (2.11.0)
              rake

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          rake
          sneakers

        BUNDLED WITH
          #{Bundler::VERSION}
      L

      bundle "update --verbose"

      expect(out).not_to include("Installing sneakers 2.12.0")
      expect(out).not_to include("Installing rake 12.3.3")
      expect(out).to include("Installing sneakers 2.11.0").and include("Installing rake 13.0.6")
    end

    it "downgrades indirect dependencies if required to fulfill an explicit upgrade request" do
      build_repo4 do
        build_gem "rbs", "3.6.1"
        build_gem "rbs", "3.9.4"

        build_gem "solargraph", "0.56.0" do |s|
          s.add_dependency "rbs", "~> 3.3"
        end

        build_gem "solargraph", "0.56.2" do |s|
          s.add_dependency "rbs", "~> 3.6.1"
        end
      end

      gemfile <<~G
        source "https://gem.repo4"

        gem 'solargraph', '~> 0.56.0'
      G

      lockfile <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            rbs (3.9.4)
            solargraph (0.56.0)
              rbs (~> 3.3)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          solargraph (~> 0.56.0)

        BUNDLED WITH
          #{Bundler::VERSION}
      L

      bundle "lock --update solargraph"

      expect(lockfile).to include("solargraph (0.56.2)")
    end

    it "does not downgrade direct dependencies unnecessarily" do
      build_repo4 do
        build_gem "redis", "4.8.1"
        build_gem "redis", "5.3.0"

        build_gem "sidekiq", "6.5.5" do |s|
          s.add_dependency "redis", ">= 4.5.0"
        end

        build_gem "sidekiq", "6.5.12" do |s|
          s.add_dependency "redis", ">= 4.5.0", "< 5"
        end

        # one version of sidekiq above Gemfile's range is needed to make the
        # resolver choose `redis` first and trying to upgrade it, reproducing
        # the accidental sidekiq downgrade as a result
        build_gem "sidekiq", "7.0.0 " do |s|
          s.add_dependency "redis", ">= 4.2.0"
        end

        build_gem "sentry-sidekiq", "5.22.0" do |s|
          s.add_dependency "sidekiq", ">= 3.0"
        end

        build_gem "sentry-sidekiq", "5.22.4" do |s|
          s.add_dependency "sidekiq", ">= 3.0"
        end
      end

      gemfile <<~G
        source "https://gem.repo4"

        gem "redis"
        gem "sidekiq", "~> 6.5"
        gem "sentry-sidekiq"
      G

      original_lockfile = <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            redis (4.8.1)
            sentry-sidekiq (5.22.0)
              sidekiq (>= 3.0)
            sidekiq (6.5.12)
              redis (>= 4.5.0, < 5)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          redis
          sentry-sidekiq
          sidekiq (~> 6.5)

        BUNDLED WITH
          #{Bundler::VERSION}
      L

      lockfile original_lockfile

      bundle "lock --update sentry-sidekiq"

      expect(lockfile).to eq(original_lockfile.sub("sentry-sidekiq (5.22.0)", "sentry-sidekiq (5.22.4)"))
    end

    it "does not downgrade indirect dependencies unnecessarily" do
      build_repo4 do
        build_gem "a" do |s|
          s.add_dependency "b"
          s.add_dependency "c"
        end
        build_gem "b"
        build_gem "c"
        build_gem "c", "2.0"
      end

      install_gemfile <<-G, verbose: true
        source "https://gem.repo4"
        gem "a"
      G

      expect(the_bundle).to include_gems("a 1.0", "b 1.0", "c 2.0")

      build_repo4 do
        build_gem "b", "2.0" do |s|
          s.add_dependency "c", "< 2"
        end
      end

      bundle "update", all: true, verbose: true
      expect(the_bundle).to include_gems("a 1.0", "b 1.0", "c 2.0")
    end

    it "should still downgrade if forced by the Gemfile" do
      build_repo4 do
        build_gem "a"
        build_gem "b", "1.0"
        build_gem "b", "2.0"
      end

      install_gemfile <<-G
        source "https://gem.repo4"
        gem "a"
        gem "b"
      G

      expect(the_bundle).to include_gems("a 1.0", "b 2.0")

      gemfile <<-G
        source "https://gem.repo4"
        gem "a"
        gem "b", "1.0"
      G

      bundle "update b"

      expect(the_bundle).to include_gems("a 1.0", "b 1.0")
    end

    it "should still downgrade if forced by the Gemfile, when transitive dependencies also need downgrade" do
      build_repo4 do
        build_gem "activesupport", "6.1.4.1" do |s|
          s.add_dependency "tzinfo", "~> 2.0"
        end

        build_gem "activesupport", "6.0.4.1" do |s|
          s.add_dependency "tzinfo", "~> 1.1"
        end

        build_gem "tzinfo", "2.0.4"
        build_gem "tzinfo", "1.2.9"
      end

      install_gemfile <<-G
        source "https://gem.repo4"
        gem "activesupport", "~> 6.1.0"
      G

      expect(the_bundle).to include_gems("activesupport 6.1.4.1", "tzinfo 2.0.4")

      gemfile <<-G
        source "https://gem.repo4"
        gem "activesupport", "~> 6.0.0"
      G

      original_lockfile = lockfile

      checksums = checksums_section_when_enabled do |c|
        c.checksum gem_repo4, "activesupport", "6.0.4.1"
        c.checksum gem_repo4, "tzinfo", "1.2.9"
      end

      expected_lockfile = <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            activesupport (6.0.4.1)
              tzinfo (~> 1.1)
            tzinfo (1.2.9)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          activesupport (~> 6.0.0)
        #{checksums}
        BUNDLED WITH
          #{Bundler::VERSION}
      L

      bundle "update activesupport"
      expect(the_bundle).to include_gems("activesupport 6.0.4.1", "tzinfo 1.2.9")
      expect(lockfile).to eq(expected_lockfile)

      lockfile original_lockfile
      bundle "update"
      expect(the_bundle).to include_gems("activesupport 6.0.4.1", "tzinfo 1.2.9")
      expect(lockfile).to eq(expected_lockfile)

      lockfile original_lockfile
      bundle "lock --update"
      expect(the_bundle).to include_gems("activesupport 6.0.4.1", "tzinfo 1.2.9")
      expect(lockfile).to eq(expected_lockfile)
    end
  end

  describe "with --local option" do
    before do
      build_repo2

      gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport"
        gem "myrack-obama"
        gem "platform_specific"
      G
    end

    it "doesn't hit repo2" do
      simulate_platform "x86-darwin-100" do
        lockfile <<~L
          GEM
            remote: https://gem.repo2/
            specs:
              activesupport (2.3.5)
              platform_specific (1.0-x86-darwin-100)
              myrack (1.0.0)
              myrack-obama (1.0)
                myrack

          PLATFORMS
            x86-darwin-100

          DEPENDENCIES
            activesupport
            platform_specific
            myrack-obama

          BUNDLED WITH
            #{Bundler::VERSION}
        L

        bundle "install"

        FileUtils.rm_r(gem_repo2)

        bundle "update --local --all"
        expect(out).not_to include("Fetching source index")
      end
    end
  end

  describe "with --group option" do
    before do
      build_repo2
    end

    it "should update only specified group gems" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport", :group => :development
        gem "myrack"
      G
      update_repo2 do
        build_gem "myrack", "1.2" do |s|
          s.executables = "myrackup"
        end

        build_gem "activesupport", "3.0"
      end
      bundle "update --group development"
      expect(the_bundle).to include_gems "activesupport 3.0"
      expect(the_bundle).not_to include_gems "myrack 1.2"
    end

    it "doesn't fail when a gem was added to the group but is not in the lockfile yet" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport", :group => :development
      G

      gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport", :group => :development
        gem "myrack", :group => :development
      G

      bundle "update --group development"

      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    context "when conservatively updating a group with non-group sub-deps" do
      it "should update only specified group gems" do
        install_gemfile <<-G
          source "https://gem.repo2"
          gem "activemerchant", :group => :development
          gem "activesupport"
        G
        update_repo2 do
          build_gem "activemerchant", "2.0"
          build_gem "activesupport", "3.0"
        end
        bundle "update --conservative --group development"
        expect(the_bundle).to include_gems "activemerchant 2.0"
        expect(the_bundle).not_to include_gems "activesupport 3.0"
      end
    end

    context "when there is a source with the same name as a gem in a group" do
      before do
        build_git "foo", path: lib_path("activesupport")
        install_gemfile <<-G
          source "https://gem.repo2"
          gem "activesupport", :group => :development
          gem "foo", :git => "#{lib_path("activesupport")}"
        G
      end

      it "should not update the gems from that source" do
        update_repo2 { build_gem "activesupport", "3.0" }
        update_git "foo", "2.0", path: lib_path("activesupport")

        bundle "update --group development"
        expect(the_bundle).to include_gems "activesupport 3.0"
        expect(the_bundle).not_to include_gems "foo 2.0"
      end
    end

    context "when bundler itself is a transitive dependency" do
      it "executes without error" do
        install_gemfile <<-G
          source "https://gem.repo1"
          gem "activesupport", :group => :development
          gem "myrack"
        G
        update_repo2 do
          build_gem "myrack", "1.2" do |s|
            s.executables = "myrackup"
          end

          build_gem "activesupport", "3.0"
        end
        bundle "update --group development"
        expect(the_bundle).to include_gems "activesupport 2.3.5"
        expect(the_bundle).to include_gems "bundler #{Bundler::VERSION}"
        expect(the_bundle).not_to include_gems "myrack 1.2"
      end
    end
  end

  describe "in a frozen bundle" do
    before do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport"
        gem "myrack-obama"
        gem "platform_specific"
      G
    end

    it "should fail loudly" do
      bundle_config "deployment true"
      bundle "update", all: true, raise_on_error: false

      expect(last_command).to be_failure
      expect(err).to eq <<~ERROR.strip
        Bundler is unlocking, but the lockfile can't be updated because frozen mode is set

        If this is a development machine, remove the Gemfile.lock freeze by running `bundle config set frozen false`.
      ERROR
    end

    it "should fail loudly when frozen is set globally" do
      bundle_config_global "frozen 1"
      bundle "update", all: true, raise_on_error: false
      expect(err).to eq <<~ERROR.strip
        Bundler is unlocking, but the lockfile can't be updated because frozen mode is set

        If this is a development machine, remove the Gemfile.lock freeze by running `bundle config set frozen false`.
      ERROR
    end

    it "should fail loudly when deployment is set globally" do
      bundle_config_global "deployment true"
      bundle "update", all: true, raise_on_error: false
      expect(err).to eq <<~ERROR.strip
        Bundler is unlocking, but the lockfile can't be updated because frozen mode is set

        If this is a development machine, remove the Gemfile.lock freeze by running `bundle config set frozen false`.
      ERROR
    end

    it "should not suggest any command to unfreeze bundler if frozen is set through ENV" do
      bundle "update", all: true, raise_on_error: false, env: { "BUNDLE_FROZEN" => "true" }
      expect(err).to eq("Bundler is unlocking, but the lockfile can't be updated because frozen mode is set")
    end
  end

  describe "with --source option" do
    before do
      build_repo2
    end

    it "should not update gems not included in the source that happen to have the same name" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport"
      G
      update_repo2 { build_gem "activesupport", "3.0" }

      bundle "update --source activesupport"
      expect(the_bundle).not_to include_gem "activesupport 3.0"
    end

    it "should not update gems not included in the source that happen to have the same name" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "activesupport"
      G
      update_repo2 { build_gem "activesupport", "3.0" }

      bundle "update --source activesupport"
      expect(the_bundle).not_to include_gems "activesupport 3.0"
    end
  end

  context "when there is a child dependency that is also in the gemfile" do
    before do
      build_repo2 do
        build_gem "fred", "1.0"
        build_gem "harry", "1.0" do |s|
          s.add_dependency "fred"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "harry"
        gem "fred"
      G
    end

    it "should not update the child dependencies of a gem that has the same name as the source" do
      update_repo2 do
        build_gem "fred", "2.0"
        build_gem "harry", "2.0" do |s|
          s.add_dependency "fred"
        end
      end

      bundle "update --source harry"
      expect(the_bundle).to include_gems "harry 1.0", "fred 1.0"
    end
  end

  context "when there is a child dependency that appears elsewhere in the dependency graph" do
    before do
      build_repo2 do
        build_gem "fred", "1.0" do |s|
          s.add_dependency "george"
        end
        build_gem "george", "1.0"
        build_gem "harry", "1.0" do |s|
          s.add_dependency "george"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "harry"
        gem "fred"
      G
    end

    it "should not update the child dependencies of a gem that has the same name as the source" do
      update_repo2 do
        build_gem "george", "2.0"
        build_gem "harry", "2.0" do |s|
          s.add_dependency "george"
        end
      end

      bundle "update --source harry"
      expect(the_bundle).to include_gems "harry 1.0", "fred 1.0", "george 1.0"
    end
  end

  it "shows the previous version of the gem when updated from rubygems source" do
    build_repo2

    install_gemfile <<-G
      source "https://gem.repo2"
      gem "activesupport"
    G

    bundle "update", all: true, verbose: true
    expect(out).to include("Using activesupport 2.3.5")

    update_repo2 do
      build_gem "activesupport", "3.0"
    end

    bundle "update", all: true
    expect(out).to include("Installing activesupport 3.0 (was 2.3.5)")
  end

  it "only prints `Using` for versions that have changed" do
    build_repo4 do
      build_gem "bar"
      build_gem "foo"
    end

    install_gemfile <<-G
      source "https://gem.repo4"
      gem "bar"
      gem "foo"
    G

    bundle "update", all: true
    expect(out).to match(/Resolving dependencies\.\.\.\.*\nBundle updated!/)

    build_repo4 do
      build_gem "foo", "2.0"
    end

    bundle "update", all: true
    expect(out.sub("Removing foo (1.0)\n", "")).to match(/Resolving dependencies\.\.\.\.*\nFetching foo 2\.0 \(was 1\.0\)\nInstalling foo 2\.0 \(was 1\.0\)\nBundle updated/)
  end

  it "shows error message when Gemfile.lock is not preset and gem is specified" do
    gemfile <<-G
      source "https://gem.repo2"
      gem "activesupport"
    G

    bundle "update nonexisting", raise_on_error: false
    expect(err).to include("This Bundle hasn't been installed yet. Run `bundle install` to update and install the bundled gems.")
    expect(exitstatus).to eq(22)
  end

  context "with multiple sources and caching enabled" do
    before do
      build_repo2 do
        build_gem "myrack", "1.0.0"

        build_gem "request_store", "1.0.0" do |s|
          s.add_dependency "myrack", "1.0.0"
        end
      end

      build_repo4 do
        # set up repo with no gems
      end

      gemfile <<~G
        source "https://gem.repo2"

        gem "request_store"

        source "https://gem.repo4" do
        end
      G

      lockfile <<~L
        GEM
          remote: https://gem.repo2/
          specs:
            myrack (1.0.0)
            request_store (1.0.0)
              myrack (= 1.0.0)

        GEM
          remote: https://gem.repo4/
          specs:

        PLATFORMS
          #{local_platform}

        DEPENDENCIES
          request_store

        BUNDLED WITH
          #{Bundler::VERSION}
      L
    end

    it "works" do
      bundle :install
      bundle :cache

      update_repo2 do
        build_gem "request_store", "1.1.0" do |s|
          s.add_dependency "myrack", "1.0.0"
        end
      end

      bundle "update request_store"

      expect(out).to include("Bundle updated!")

      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo2/
          specs:
            myrack (1.0.0)
            request_store (1.1.0)
              myrack (= 1.0.0)

        GEM
          remote: https://gem.repo4/
          specs:

        PLATFORMS
          #{local_platform}

        DEPENDENCIES
          request_store

        BUNDLED WITH
          #{Bundler::VERSION}
      L
    end
  end
end
