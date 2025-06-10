# frozen_string_literal: true

RSpec.describe "bundle cache" do
  it "doesn't update the cache multiple times, even if it already exists" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    bundle :cache
    expect(out).to include("Updating files in vendor/cache").once

    bundle :cache
    expect(out).to include("Updating files in vendor/cache").once
  end

  context "with --gemfile" do
    it "finds the gemfile" do
      gemfile bundled_app("NotGemfile"), <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G

      bundle "cache --gemfile=NotGemfile"

      ENV["BUNDLE_GEMFILE"] = "NotGemfile"
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end
  end

  context "with --all" do
    context "without a gemspec" do
      it "caches all dependencies except bundler itself" do
        gemfile <<-D
          source "https://gem.repo1"
          gem 'myrack'
          gem 'bundler'
        D

        bundle "config set cache_all true"
        bundle :cache

        expect(bundled_app("vendor/cache/myrack-1.0.0.gem")).to exist
        expect(bundled_app("vendor/cache/bundler-0.9.gem")).to_not exist
      end
    end

    context "with a gemspec" do
      context "that has the same name as the gem" do
        before do
          File.open(bundled_app("mygem.gemspec"), "w") do |f|
            f.write <<-G
              Gem::Specification.new do |s|
                s.name = "mygem"
                s.version = "0.1.1"
                s.summary = ""
                s.authors = ["gem author"]
                s.add_development_dependency "nokogiri", "=1.4.2"
              end
            G
          end
        end

        it "caches all dependencies except bundler and the gemspec specified gem" do
          gemfile <<-D
            source "https://gem.repo1"
            gem 'myrack'
            gemspec
          D

          bundle "config set cache_all true"
          bundle :cache

          expect(bundled_app("vendor/cache/myrack-1.0.0.gem")).to exist
          expect(bundled_app("vendor/cache/nokogiri-1.4.2.gem")).to exist
          expect(bundled_app("vendor/cache/mygem-0.1.1.gem")).to_not exist
          expect(bundled_app("vendor/cache/bundler-0.9.gem")).to_not exist
        end
      end

      context "that has a different name as the gem" do
        before do
          File.open(bundled_app("mygem_diffname.gemspec"), "w") do |f|
            f.write <<-G
              Gem::Specification.new do |s|
                s.name = "mygem"
                s.version = "0.1.1"
                s.summary = ""
                s.authors = ["gem author"]
                s.add_development_dependency "nokogiri", "=1.4.2"
              end
            G
          end
        end

        it "caches all dependencies except bundler and the gemspec specified gem" do
          gemfile <<-D
            source "https://gem.repo1"
            gem 'myrack'
            gemspec
          D

          bundle "config set cache_all true"
          bundle :cache

          expect(bundled_app("vendor/cache/myrack-1.0.0.gem")).to exist
          expect(bundled_app("vendor/cache/nokogiri-1.4.2.gem")).to exist
          expect(bundled_app("vendor/cache/mygem-0.1.1.gem")).to_not exist
          expect(bundled_app("vendor/cache/bundler-0.9.gem")).to_not exist
        end
      end
    end

    context "with multiple gemspecs" do
      before do
        File.open(bundled_app("mygem.gemspec"), "w") do |f|
          f.write <<-G
            Gem::Specification.new do |s|
              s.name = "mygem"
              s.version = "0.1.1"
              s.summary = ""
              s.authors = ["gem author"]
              s.add_development_dependency "nokogiri", "=1.4.2"
            end
          G
        end
        File.open(bundled_app("mygem_client.gemspec"), "w") do |f|
          f.write <<-G
            Gem::Specification.new do |s|
              s.name = "mygem_test"
              s.version = "0.1.1"
              s.summary = ""
              s.authors = ["gem author"]
              s.add_development_dependency "weakling", "=0.0.3"
            end
          G
        end
      end

      it "caches all dependencies except bundler and the gemspec specified gems" do
        gemfile <<-D
          source "https://gem.repo1"
          gem 'myrack'
          gemspec :name => 'mygem'
          gemspec :name => 'mygem_test'
        D

        bundle "config set cache_all true"
        bundle :cache

        expect(bundled_app("vendor/cache/myrack-1.0.0.gem")).to exist
        expect(bundled_app("vendor/cache/nokogiri-1.4.2.gem")).to exist
        expect(bundled_app("vendor/cache/weakling-0.0.3.gem")).to exist
        expect(bundled_app("vendor/cache/mygem-0.1.1.gem")).to_not exist
        expect(bundled_app("vendor/cache/mygem_test-0.1.1.gem")).to_not exist
        expect(bundled_app("vendor/cache/bundler-0.9.gem")).to_not exist
      end
    end
  end

  context "with --path", bundler: "2" do
    it "sets root directory for gems" do
      gemfile <<-D
        source "https://gem.repo1"
        gem 'myrack'
      D

      bundle "cache --path #{bundled_app("test")}"

      expect(the_bundle).to include_gems "myrack 1.0.0"
      expect(bundled_app("test/vendor/cache/")).to exist
    end
  end

  context "with --no-install" do
    it "puts the gems in vendor/cache but does not install them" do
      gemfile <<-D
        source "https://gem.repo1"
        gem 'myrack'
      D

      bundle "cache --no-install"

      expect(the_bundle).not_to include_gems "myrack 1.0.0"
      expect(bundled_app("vendor/cache/myrack-1.0.0.gem")).to exist
    end

    it "does not prevent installing gems with bundle install" do
      gemfile <<-D
        source "https://gem.repo1"
        gem 'myrack'
      D

      bundle "cache --no-install"
      bundle "install"

      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "does not prevent installing gems with bundle update" do
      gemfile <<-D
        source "https://gem.repo1"
        gem "myrack", "1.0.0"
      D

      bundle "cache --no-install"
      bundle "update --all"

      expect(the_bundle).to include_gems "myrack 1.0.0"
    end
  end

  context "with --all-platforms" do
    it "puts the gems in vendor/cache even for other rubies" do
      gemfile <<-D
        source "https://gem.repo1"
        gem 'myrack', :platforms => [:ruby_20, :windows_20]
      D

      bundle "cache --all-platforms"
      expect(bundled_app("vendor/cache/myrack-1.0.0.gem")).to exist
    end

    it "puts the gems in vendor/cache even for legacy windows rubies, but prints a warning", bundler: "2" do
      gemfile <<-D
        source "https://gem.repo1"
        gem 'myrack', :platforms => [:ruby_20, :x64_mingw_20]
      D

      bundle "cache --all-platforms"
      expect(err).to include("deprecated")
      expect(bundled_app("vendor/cache/myrack-1.0.0.gem")).to exist
    end

    it "prints an error when using legacy windows rubies", bundler: "3" do
      gemfile <<-D
        source "https://gem.repo1"
        gem 'myrack', :platforms => [:ruby_20, :x64_mingw_20]
      D

      bundle "cache --all-platforms", raise_on_error: false
      expect(err).to include("removed")
      expect(bundled_app("vendor/cache/myrack-1.0.0.gem")).not_to exist
    end

    it "does not attempt to install gems in without groups" do
      build_repo4 do
        build_gem "uninstallable", "2.0" do |s|
          s.add_development_dependency "rake"
          s.extensions << "Rakefile"
          s.write "Rakefile", "task(:default) { raise 'CANNOT INSTALL' }"
        end
      end

      bundle "config set --local without wo"
      install_gemfile <<-G, artifice: "compact_index_extra_api"
        source "https://main.repo"
        gem "myrack"
        group :wo do
          gem "weakling"
          gem "uninstallable", :source => "https://main.repo/extra"
        end
      G

      bundle :cache, "all-platforms" => true, artifice: "compact_index_extra_api"
      expect(bundled_app("vendor/cache/weakling-0.0.3.gem")).to exist
      expect(bundled_app("vendor/cache/uninstallable-2.0.gem")).to exist
      expect(the_bundle).to include_gem "myrack 1.0"
      expect(the_bundle).not_to include_gems "weakling", "uninstallable"

      bundle "config set --local without wo"
      bundle :install, artifice: "compact_index_extra_api"
      expect(the_bundle).to include_gem "myrack 1.0"
      expect(the_bundle).not_to include_gems "weakling"
    end

    it "does not fail to cache gems in excluded groups when there's a lockfile but gems not previously installed" do
      bundle "config set --local without wo"
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        group :wo do
          gem "weakling"
        end
      G

      bundle :lock
      bundle :cache, "all-platforms" => true
      expect(bundled_app("vendor/cache/weakling-0.0.3.gem")).to exist
    end
  end

  context "with frozen configured" do
    before do
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
      bundle "install"
    end

    subject do
      bundle "config set --local frozen true"
      bundle :cache, raise_on_error: false
    end

    it "tries to install with frozen" do
      bundle "config set deployment true"
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "myrack-obama"
      G
      subject
      expect(exitstatus).to eq(16)
      expect(err).to include("frozen mode")
      expect(err).to include("You have added to the Gemfile")
      expect(err).to include("* myrack-obama")
      bundle "env"
      expect(out).to include("frozen").or include("deployment")
    end
  end

  context "with gems with extensions" do
    before do
      build_repo2 do
        build_gem "racc", "2.0" do |s|
          s.add_dependency "rake"
          s.extensions << "Rakefile"
          s.write "Rakefile", "task(:default) { puts 'INSTALLING myrack' }"
        end
      end

      gemfile <<~G
        source "https://gem.repo2"

        gem "racc"
      G
    end

    it "installs them properly from cache to a different path" do
      bundle "cache"
      bundle "config set --local path vendor/bundle"
      bundle "install --local"
    end
  end
end

RSpec.describe "bundle install with gem sources" do
  describe "when cached and locked" do
    it "does not hit the remote at all" do
      build_repo2
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"
      G

      bundle :cache
      pristine_system_gems :bundler
      FileUtils.rm_r gem_repo2

      bundle "install --local"
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "does not hit the remote at all in frozen mode" do
      build_repo2
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"
      G

      bundle :cache
      pristine_system_gems :bundler
      FileUtils.rm_r gem_repo2

      bundle "config set --local deployment true"
      bundle "config set --local path vendor/bundle"
      bundle :install
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "does not hit the remote at all when cache_all_platforms configured" do
      build_repo2
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"
      G

      bundle :cache
      pristine_system_gems :bundler
      FileUtils.rm_r gem_repo2

      bundle "config set --local cache_all_platforms true"
      bundle "config set --local path vendor/bundle"
      bundle "install --local"
      expect(out).not_to include("Fetching gem metadata")
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "uses cached gems for secondary sources when cache_all_platforms configured" do
      build_repo4 do
        build_gem "foo", "1.0.0" do |s|
          s.platform = "x86_64-linux"
        end

        build_gem "foo", "1.0.0" do |s|
          s.platform = "arm64-darwin"
        end
      end

      gemfile <<~G
        source "https://gem.repo2"

        source "https://gem.repo4" do
        gem "foo"
        end
      G

      lockfile <<~L
        GEM
          remote: https://gem.repo2/
          specs:

        GEM
          remote: https://gem.repo4/
          specs:
            foo (1.0.0-x86_64-linux)
            foo (1.0.0-arm64-darwin)

        PLATFORMS
          arm64-darwin
          ruby
          x86_64-linux

        DEPENDENCIES
          foo

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      simulate_platform "x86_64-linux" do
        bundle "config set cache_all_platforms true"
        bundle "config set path vendor/bundle"
        bundle :cache, artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }

        # simulate removal of all remote gems
        empty_repo4

        # delete compact index cache
        FileUtils.rm_r home(".bundle/cache/compact_index")

        bundle "install", artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }

        expect(the_bundle).to include_gems "foo 1.0.0 x86_64-linux"
      end
    end

    it "does not reinstall already-installed gems" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
      bundle :cache

      build_gem "myrack", "1.0.0", path: bundled_app("vendor/cache") do |s|
        s.write "lib/myrack.rb", "raise 'omg'"
      end

      bundle :install
      expect(err).to be_empty
      expect(the_bundle).to include_gems "myrack 1.0"
    end

    it "ignores cached gems for the wrong platform" do
      simulate_platform "java" do
        install_gemfile <<-G
          source "https://gem.repo1"
          gem "platform_specific"
        G
        bundle :cache
      end

      pristine_system_gems :bundler

      bundle "config set --local force_ruby_platform true"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "platform_specific"
      G
      expect(the_bundle).to include_gems("platform_specific 1.0 ruby")
    end

    it "keeps gems that are locked and cached for the current platform, even if incompatible with the current ruby" do
      build_repo4 do
        build_gem "bcrypt_pbkdf", "1.1.1"
        build_gem "bcrypt_pbkdf", "1.1.1" do |s|
          s.platform = "arm64-darwin"
          s.required_ruby_version = "< #{current_ruby_minor}"
        end
      end

      app_cache = bundled_app("vendor/cache")
      FileUtils.mkdir_p app_cache
      FileUtils.cp gem_repo4("gems/bcrypt_pbkdf-1.1.1-arm64-darwin.gem"), app_cache
      FileUtils.cp gem_repo4("gems/bcrypt_pbkdf-1.1.1.gem"), app_cache

      bundle "config cache_all_platforms true"

      lockfile <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            bcrypt_pbkdf (1.1.1)
            bcrypt_pbkdf (1.1.1-arm64-darwin)

        PLATFORMS
          arm64-darwin
          ruby

        DEPENDENCIES
          bcrypt_pbkdf

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      simulate_platform "arm64-darwin-23" do
        install_gemfile <<~G, verbose: true
          source "https://gem.repo4"
          gem "bcrypt_pbkdf"
        G

        expect(out).to include("Updating files in vendor/cache")
        expect(err).to be_empty
        expect(app_cache.join("bcrypt_pbkdf-1.1.1-arm64-darwin.gem")).to exist
        expect(app_cache.join("bcrypt_pbkdf-1.1.1.gem")).to exist
      end
    end

    it "does not update the cache if --no-cache is passed" do
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
      bundled_app("vendor/cache").mkpath
      expect(bundled_app("vendor/cache").children).to be_empty

      bundle "install --no-cache"
      expect(bundled_app("vendor/cache").children).to be_empty
    end
  end
end
