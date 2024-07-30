# frozen_string_literal: true

RSpec.describe "bundle cache" do
  shared_examples_for "when there are only gemsources" do
    before :each do
      gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G

      system_gems "myrack-1.0.0", path: path
      bundle :cache
    end

    it "copies the .gem file to vendor/cache" do
      expect(bundled_app("vendor/cache/myrack-1.0.0.gem")).to exist
    end

    it "uses the cache as a source when installing gems" do
      build_gem "omg", path: bundled_app("vendor/cache")

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "omg"
      G

      expect(the_bundle).to include_gems "omg 1.0.0"
    end

    it "uses the cache as a source when installing gems with --local" do
      system_gems [], path: default_bundle_path
      bundle "install --local"

      expect(the_bundle).to include_gems("myrack 1.0.0")
    end

    it "does not reinstall gems from the cache if they exist on the system" do
      build_gem "myrack", "1.0.0", path: bundled_app("vendor/cache") do |s|
        s.write "lib/myrack.rb", "MYRACK = 'FAIL'"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      expect(the_bundle).to include_gems("myrack 1.0.0")
    end

    it "does not reinstall gems from the cache if they exist in the bundle" do
      system_gems "myrack-1.0.0", path: default_bundle_path

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      build_gem "myrack", "1.0.0", path: bundled_app("vendor/cache") do |s|
        s.write "lib/myrack.rb", "MYRACK = 'FAIL'"
      end

      bundle :install, local: true
      expect(the_bundle).to include_gems("myrack 1.0.0")
    end

    it "creates a lockfile" do
      cache_gems "myrack-1.0.0"

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      bundle "cache"

      expect(bundled_app_lock).to exist
    end
  end

  context "using system gems" do
    before { bundle "config set path.system true" }
    let(:path) { system_gem_path }
    it_behaves_like "when there are only gemsources"
  end

  context "installing into a local path" do
    before { bundle "config set path ./.bundle" }
    let(:path) { local_gem_path }
    it_behaves_like "when there are only gemsources"
  end

  describe "when there is a built-in gem", :ruby_repo do
    let(:default_json_version) { ruby "gem 'json'; require 'json'; puts JSON::VERSION" }

    before :each do
      build_gem "json", default_json_version, to_system: true, default: true
    end

    context "when a remote gem is available for caching" do
      before do
        build_repo2 do
          build_gem "json", default_json_version
        end
      end

      it "uses remote gems when installing to system gems" do
        bundle "config set path.system true"
        install_gemfile %(source "https://gem.repo2"; gem 'json', '#{default_json_version}'), verbose: true
        expect(out).to include("Installing json #{default_json_version}")
      end

      it "caches remote and builtin gems" do
        install_gemfile <<-G
          source "https://gem.repo2"
          gem 'json', '#{default_json_version}'
          gem 'myrack', '1.0.0'
        G

        bundle :cache
        expect(bundled_app("vendor/cache/myrack-1.0.0.gem")).to exist
        expect(bundled_app("vendor/cache/json-#{default_json_version}.gem")).to exist
      end

      it "caches builtin gems when cache_all_platforms is set" do
        gemfile <<-G
          source "https://gem.repo2"
          gem "json"
        G

        bundle "config set cache_all_platforms true"

        bundle :cache
        expect(bundled_app("vendor/cache/json-#{default_json_version}.gem")).to exist
      end

      it "doesn't make remote request after caching the gem" do
        build_gem "builtin_gem_2", "1.0.2", path: bundled_app("vendor/cache") do |s|
          s.summary = "This builtin_gem is bundled with Ruby"
        end

        install_gemfile <<-G
          source "https://gem.repo2"
          gem 'builtin_gem_2', '1.0.2'
        G

        bundle "install --local"
        expect(the_bundle).to include_gems("builtin_gem_2 1.0.2")
      end
    end

    context "when a remote gem is not available for caching" do
      it "uses builtin gems when installing to system gems" do
        bundle "config set path.system true"
        install_gemfile %(source "https://gem.repo1"; gem 'json', '#{default_json_version}'), verbose: true
        expect(out).to include("Using json #{default_json_version}")
      end

      it "errors when explicitly caching" do
        bundle "config set path.system true"

        install_gemfile <<-G
          source "https://gem.repo1"
          gem 'json', '#{default_json_version}'
        G

        bundle :cache, raise_on_error: false
        expect(exitstatus).to_not eq(0)
        expect(err).to include("json-#{default_json_version} is built in to Ruby, and can't be cached")
      end
    end
  end

  describe "when there are also git sources" do
    before do
      build_git "foo"
      system_gems "myrack-1.0.0"

      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}" do
          gem 'foo'
        end
        gem 'myrack'
      G
    end

    it "still works" do
      bundle :cache

      system_gems []
      bundle "install --local"

      expect(the_bundle).to include_gems("myrack 1.0.0", "foo 1.0")
    end

    it "should not explode if the lockfile is not present" do
      FileUtils.rm(bundled_app_lock)

      bundle :cache

      expect(bundled_app_lock).to exist
    end
  end

  describe "when previously cached" do
    let :setup_main_repo do
      build_repo2
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"
        gem "actionpack"
      G
      bundle :cache
      expect(cached_gem("myrack-1.0.0")).to exist
      expect(cached_gem("actionpack-2.3.2")).to exist
      expect(cached_gem("activesupport-2.3.2")).to exist
    end

    it "re-caches during install" do
      setup_main_repo
      cached_gem("myrack-1.0.0").rmtree
      bundle :install
      expect(out).to include("Updating files in vendor/cache")
      expect(cached_gem("myrack-1.0.0")).to exist
    end

    it "adds and removes when gems are updated" do
      setup_main_repo
      update_repo2 do
        build_gem "myrack", "1.2" do |s|
          s.executables = "myrackup"
        end
      end

      bundle "update", all: true
      expect(cached_gem("myrack-1.2")).to exist
      expect(cached_gem("myrack-1.0.0")).not_to exist
    end

    it "adds new gems and dependencies" do
      setup_main_repo
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "rails"
      G
      expect(cached_gem("rails-2.3.2")).to exist
      expect(cached_gem("activerecord-2.3.2")).to exist
    end

    it "removes .gems for removed gems and dependencies" do
      setup_main_repo
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"
      G
      expect(cached_gem("myrack-1.0.0")).to exist
      expect(cached_gem("actionpack-2.3.2")).not_to exist
      expect(cached_gem("activesupport-2.3.2")).not_to exist
    end

    it "removes .gems when gem changes to git source" do
      setup_main_repo
      build_git "myrack"

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack", :git => "#{lib_path("myrack-1.0")}"
        gem "actionpack"
      G
      expect(cached_gem("myrack-1.0.0")).not_to exist
      expect(cached_gem("actionpack-2.3.2")).to exist
      expect(cached_gem("activesupport-2.3.2")).to exist
    end

    it "doesn't remove gems that are for another platform" do
      simulate_platform "java" do
        install_gemfile <<-G
          source "https://gem.repo1"
          gem "platform_specific"
        G

        bundle :cache
        expect(cached_gem("platform_specific-1.0-java")).to exist
      end

      simulate_new_machine

      simulate_platform "x86-darwin-100" do
        install_gemfile <<-G
          source "https://gem.repo1"
          gem "platform_specific"
        G

        expect(cached_gem("platform_specific-1.0-x86-darwin-100")).to exist
        expect(cached_gem("platform_specific-1.0-java")).to exist
      end
    end

    it "doesn't remove gems cached gems that don't match their remote counterparts, but also refuses to install and prints an error" do
      setup_main_repo
      cached_myrack = cached_gem("myrack-1.0.0")
      cached_myrack.rmtree
      build_gem "myrack", "1.0.0",
        path: cached_myrack.parent,
        rubygems_version: "1.3.2"

      simulate_new_machine

      FileUtils.rm bundled_app_lock
      bundle :install, raise_on_error: false

      expect(err).to eq <<~E.strip
        Bundler found mismatched checksums. This is a potential security risk.
          #{checksum_to_lock(gem_repo2, "myrack", "1.0.0")}
            from the API at https://gem.repo2/
          #{checksum_from_package(cached_myrack, "myrack", "1.0.0")}
            from the gem at #{cached_myrack}

        If you trust the API at https://gem.repo2/, to resolve this issue you can:
          1. remove the gem at #{cached_myrack}
          2. run `bundle install`

        To ignore checksum security warnings, disable checksum validation with
          `bundle config set --local disable_checksum_validation true`
      E

      expect(cached_gem("myrack-1.0.0")).to exist
    end

    it "raises an error when a cached gem is altered and produces a different checksum than the remote gem" do
      setup_main_repo
      cached_gem("myrack-1.0.0").rmtree
      build_gem "myrack", "1.0.0", path: bundled_app("vendor/cache")

      checksums = checksums_section do |c|
        c.checksum gem_repo1, "myrack", "1.0.0"
      end

      simulate_new_machine

      lockfile <<-L
        GEM
          remote: https://gem.repo2/
          specs:
            myrack (1.0.0)
        #{checksums}
      L

      bundle :install, raise_on_error: false
      expect(exitstatus).to eq(37)
      expect(err).to include("Bundler found mismatched checksums.")
      expect(err).to include("1. remove the gem at #{cached_gem("myrack-1.0.0")}")

      expect(cached_gem("myrack-1.0.0")).to exist
      cached_gem("myrack-1.0.0").rmtree
      bundle :install
      expect(cached_gem("myrack-1.0.0")).to exist
    end

    it "installs a modified gem with a non-matching checksum when the API implementation does not provide checksums" do
      setup_main_repo
      cached_gem("myrack-1.0.0").rmtree
      build_gem "myrack", "1.0.0", path: bundled_app("vendor/cache")
      simulate_new_machine

      lockfile <<-L
        GEM
          remote: https://gem.repo2/
          specs:
            myrack (1.0.0)
      L

      bundle :install, artifice: "endpoint", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
      expect(cached_gem("myrack-1.0.0")).to exist
    end

    it "handles directories and non .gem files in the cache" do
      setup_main_repo
      bundled_app("vendor/cache/foo").mkdir
      File.open(bundled_app("vendor/cache/bar"), "w") {|f| f.write("not a gem") }
      bundle :cache
    end

    it "does not say that it is removing gems when it isn't actually doing so" do
      setup_main_repo
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
      bundle "cache"
      bundle "install"
      expect(out).not_to match(/removing/i)
    end

    it "does not warn about all if it doesn't have any git/path dependency" do
      setup_main_repo
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
      bundle "cache"
      expect(out).not_to match(/\-\-all/)
    end

    it "should install gems with the name bundler in them (that aren't bundler)" do
      build_gem "foo-bundler", "1.0",
        path: bundled_app("vendor/cache")

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo-bundler"
      G

      expect(the_bundle).to include_gems "foo-bundler 1.0"
    end
  end
end
