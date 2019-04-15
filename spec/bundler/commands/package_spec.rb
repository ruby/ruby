# frozen_string_literal: true

RSpec.describe "bundle package" do
  context "with --gemfile" do
    it "finds the gemfile" do
      gemfile bundled_app("NotGemfile"), <<-G
        source "file://#{gem_repo1}"
        gem 'rack'
      G

      bundle "package --gemfile=NotGemfile"

      ENV["BUNDLE_GEMFILE"] = "NotGemfile"
      expect(the_bundle).to include_gems "rack 1.0.0"
    end
  end

  context "with --all" do
    context "without a gemspec" do
      it "caches all dependencies except bundler itself" do
        gemfile <<-D
          source "file://#{gem_repo1}"
          gem 'rack'
          gem 'bundler'
        D

        bundle :package, forgotten_command_line_options([:all, :cache_all] => true)

        expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
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
            source "file://#{gem_repo1}"
            gem 'rack'
            gemspec
          D

          bundle! :package, forgotten_command_line_options([:all, :cache_all] => true)

          expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
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
            source "file://#{gem_repo1}"
            gem 'rack'
            gemspec
          D

          bundle! :package, forgotten_command_line_options([:all, :cache_all] => true)

          expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
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
          source "file://#{gem_repo1}"
          gem 'rack'
          gemspec :name => 'mygem'
          gemspec :name => 'mygem_test'
        D

        bundle! :package, forgotten_command_line_options([:all, :cache_all] => true)

        expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
        expect(bundled_app("vendor/cache/nokogiri-1.4.2.gem")).to exist
        expect(bundled_app("vendor/cache/weakling-0.0.3.gem")).to exist
        expect(bundled_app("vendor/cache/mygem-0.1.1.gem")).to_not exist
        expect(bundled_app("vendor/cache/mygem_test-0.1.1.gem")).to_not exist
        expect(bundled_app("vendor/cache/bundler-0.9.gem")).to_not exist
      end
    end
  end

  context "with --path", :bundler => "< 3" do
    it "sets root directory for gems" do
      gemfile <<-D
        source "file://#{gem_repo1}"
        gem 'rack'
      D

      bundle! :package, forgotten_command_line_options(:path => bundled_app("test"))

      expect(the_bundle).to include_gems "rack 1.0.0"
      expect(bundled_app("test/vendor/cache/")).to exist
    end
  end

  context "with --no-install" do
    it "puts the gems in vendor/cache but does not install them" do
      gemfile <<-D
        source "file://#{gem_repo1}"
        gem 'rack'
      D

      bundle! "package --no-install"

      expect(the_bundle).not_to include_gems "rack 1.0.0"
      expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
    end

    it "does not prevent installing gems with bundle install" do
      gemfile <<-D
        source "file://#{gem_repo1}"
        gem 'rack'
      D

      bundle! "package --no-install"
      bundle! "install"

      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "does not prevent installing gems with bundle update" do
      gemfile <<-D
        source "file://#{gem_repo1}"
        gem "rack", "1.0.0"
      D

      bundle! "package --no-install"
      bundle! "update --all"

      expect(the_bundle).to include_gems "rack 1.0.0"
    end
  end

  context "with --all-platforms" do
    it "puts the gems in vendor/cache even for other rubies" do
      gemfile <<-D
        source "file://#{gem_repo1}"
        gem 'rack', :platforms => :ruby_19
      D

      bundle "package --all-platforms"
      expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
    end
  end

  context "with --frozen" do
    before do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G
      bundle "install"
    end

    subject { bundle :package, forgotten_command_line_options(:frozen => true) }

    it "tries to install with frozen" do
      bundle! "config set deployment true"
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
        gem "rack-obama"
      G
      subject
      expect(exitstatus).to eq(16) if exitstatus
      expect(err).to include("deployment mode")
      expect(err).to include("You have added to the Gemfile")
      expect(err).to include("* rack-obama")
      bundle "env"
      expect(out).to include("frozen").or include("deployment")
    end
  end
end

RSpec.describe "bundle install with gem sources" do
  describe "when cached and locked" do
    it "does not hit the remote at all" do
      build_repo2
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "rack"
      G

      bundle :pack
      simulate_new_machine
      FileUtils.rm_rf gem_repo2

      bundle "install --local"
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "does not hit the remote at all" do
      build_repo2
      install_gemfile! <<-G
        source "file://#{gem_repo2}"
        gem "rack"
      G

      bundle! :pack
      simulate_new_machine
      FileUtils.rm_rf gem_repo2

      bundle! :install, forgotten_command_line_options(:deployment => true, :path => "vendor/bundle")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "does not reinstall already-installed gems" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G
      bundle :pack

      build_gem "rack", "1.0.0", :path => bundled_app("vendor/cache") do |s|
        s.write "lib/rack.rb", "raise 'omg'"
      end

      bundle :install
      expect(last_command.stderr).to be_empty
      expect(the_bundle).to include_gems "rack 1.0"
    end

    it "ignores cached gems for the wrong platform" do
      simulate_platform "java" do
        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "platform_specific"
        G
        bundle :pack
      end

      simulate_new_machine

      simulate_platform "ruby" do
        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "platform_specific"
        G
        run "require 'platform_specific' ; puts PLATFORM_SPECIFIC"
        expect(out).to eq("1.0.0 RUBY")
      end
    end

    it "does not update the cache if --no-cache is passed" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G
      bundled_app("vendor/cache").mkpath
      expect(bundled_app("vendor/cache").children).to be_empty

      bundle "install --no-cache"
      expect(bundled_app("vendor/cache").children).to be_empty
    end
  end
end
