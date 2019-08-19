# frozen_string_literal: true

RSpec.describe "bundle cache" do
  shared_examples_for "when there are only gemsources" do
    before :each do
      gemfile <<-G
        gem 'rack'
      G

      system_gems "rack-1.0.0", :path => :bundle_path
      bundle! :cache
    end

    it "copies the .gem file to vendor/cache" do
      expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
    end

    it "uses the cache as a source when installing gems" do
      build_gem "omg", :path => bundled_app("vendor/cache")

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "omg"
      G

      expect(the_bundle).to include_gems "omg 1.0.0"
    end

    it "uses the cache as a source when installing gems with --local" do
      system_gems [], :path => :bundle_path
      bundle "install --local"

      expect(the_bundle).to include_gems("rack 1.0.0")
    end

    it "does not reinstall gems from the cache if they exist on the system" do
      build_gem "rack", "1.0.0", :path => bundled_app("vendor/cache") do |s|
        s.write "lib/rack.rb", "RACK = 'FAIL'"
      end

      install_gemfile <<-G
        gem "rack"
      G

      expect(the_bundle).to include_gems("rack 1.0.0")
    end

    it "does not reinstall gems from the cache if they exist in the bundle" do
      system_gems "rack-1.0.0", :path => :bundle_path

      gemfile <<-G
        gem "rack"
      G

      build_gem "rack", "1.0.0", :path => bundled_app("vendor/cache") do |s|
        s.write "lib/rack.rb", "RACK = 'FAIL'"
      end

      bundle! :install, :local => true
      expect(the_bundle).to include_gems("rack 1.0.0")
    end

    it "creates a lockfile" do
      cache_gems "rack-1.0.0"

      gemfile <<-G
        gem "rack"
      G

      bundle "cache"

      expect(bundled_app("Gemfile.lock")).to exist
    end
  end

  context "using system gems" do
    before { bundle! "config set path.system true" }
    it_behaves_like "when there are only gemsources"
  end

  context "installing into a local path" do
    before { bundle! "config set path ./.bundle" }
    it_behaves_like "when there are only gemsources"
  end

  describe "when there is a built-in gem" do
    before :each do
      build_repo2 do
        build_gem "builtin_gem", "1.0.2"
      end

      build_gem "builtin_gem", "1.0.2", :to_system => true do |s|
        s.summary = "This builtin_gem is bundled with Ruby"
      end

      FileUtils.rm("#{system_gem_path}/cache/builtin_gem-1.0.2.gem")
    end

    it "uses builtin gems when installing to system gems" do
      bundle! "config set path.system true"
      install_gemfile %(gem 'builtin_gem', '1.0.2')
      expect(the_bundle).to include_gems("builtin_gem 1.0.2")
    end

    it "caches remote and builtin gems" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem 'builtin_gem', '1.0.2'
        gem 'rack', '1.0.0'
      G

      bundle :cache
      expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
      expect(bundled_app("vendor/cache/builtin_gem-1.0.2.gem")).to exist
    end

    it "doesn't make remote request after caching the gem" do
      build_gem "builtin_gem_2", "1.0.2", :path => bundled_app("vendor/cache") do |s|
        s.summary = "This builtin_gem is bundled with Ruby"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem 'builtin_gem_2', '1.0.2'
      G

      bundle "install --local"
      expect(the_bundle).to include_gems("builtin_gem_2 1.0.2")
    end

    it "errors if the builtin gem isn't available to cache" do
      bundle! "config set path.system true"

      install_gemfile <<-G
        gem 'builtin_gem', '1.0.2'
      G

      bundle :cache
      expect(exitstatus).to_not eq(0) if exitstatus
      expect(err).to include("builtin_gem-1.0.2 is built in to Ruby, and can't be cached")
    end
  end

  describe "when there are also git sources" do
    before do
      build_git "foo"
      system_gems "rack-1.0.0"

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        git "#{lib_path("foo-1.0")}" do
          gem 'foo'
        end
        gem 'rack'
      G
    end

    it "still works" do
      bundle :cache

      system_gems []
      bundle "install --local"

      expect(the_bundle).to include_gems("rack 1.0.0", "foo 1.0")
    end

    it "should not explode if the lockfile is not present" do
      FileUtils.rm(bundled_app("Gemfile.lock"))

      bundle :cache

      expect(bundled_app("Gemfile.lock")).to exist
    end
  end

  describe "when previously cached" do
    before :each do
      build_repo2
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack"
        gem "actionpack"
      G
      bundle :cache
      expect(cached_gem("rack-1.0.0")).to exist
      expect(cached_gem("actionpack-2.3.2")).to exist
      expect(cached_gem("activesupport-2.3.2")).to exist
    end

    it "re-caches during install" do
      cached_gem("rack-1.0.0").rmtree
      bundle :install
      expect(out).to include("Updating files in vendor/cache")
      expect(cached_gem("rack-1.0.0")).to exist
    end

    it "adds and removes when gems are updated" do
      update_repo2
      bundle "update", :all => true
      expect(cached_gem("rack-1.2")).to exist
      expect(cached_gem("rack-1.0.0")).not_to exist
    end

    it "adds new gems and dependencies" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rails"
      G
      expect(cached_gem("rails-2.3.2")).to exist
      expect(cached_gem("activerecord-2.3.2")).to exist
    end

    it "removes .gems for removed gems and dependencies" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack"
      G
      expect(cached_gem("rack-1.0.0")).to exist
      expect(cached_gem("actionpack-2.3.2")).not_to exist
      expect(cached_gem("activesupport-2.3.2")).not_to exist
    end

    it "removes .gems when gem changes to git source" do
      build_git "rack"

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack", :git => "#{lib_path("rack-1.0")}"
        gem "actionpack"
      G
      expect(cached_gem("rack-1.0.0")).not_to exist
      expect(cached_gem("actionpack-2.3.2")).to exist
      expect(cached_gem("activesupport-2.3.2")).to exist
    end

    it "doesn't remove gems that are for another platform" do
      simulate_platform "java" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "platform_specific"
        G

        bundle :cache
        expect(cached_gem("platform_specific-1.0-java")).to exist
      end

      simulate_new_machine
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "platform_specific"
      G

      expect(cached_gem("platform_specific-1.0-#{Bundler.local_platform}")).to exist
      expect(cached_gem("platform_specific-1.0-java")).to exist
    end

    it "doesn't remove gems with mismatched :rubygems_version or :date" do
      cached_gem("rack-1.0.0").rmtree
      build_gem "rack", "1.0.0",
        :path => bundled_app("vendor/cache"),
        :rubygems_version => "1.3.2"
      simulate_new_machine

      bundle :install
      expect(cached_gem("rack-1.0.0")).to exist
    end

    it "handles directories and non .gem files in the cache" do
      bundled_app("vendor/cache/foo").mkdir
      File.open(bundled_app("vendor/cache/bar"), "w") {|f| f.write("not a gem") }
      bundle :cache
    end

    it "does not say that it is removing gems when it isn't actually doing so" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
      bundle "cache"
      bundle "install"
      expect(out).not_to match(/removing/i)
    end

    it "does not warn about all if it doesn't have any git/path dependency" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
      bundle "cache"
      expect(out).not_to match(/\-\-all/)
    end

    it "should install gems with the name bundler in them (that aren't bundler)" do
      build_gem "foo-bundler", "1.0",
        :path => bundled_app("vendor/cache")

      install_gemfile <<-G
        gem "foo-bundler"
      G

      expect(the_bundle).to include_gems "foo-bundler 1.0"
    end
  end
end
