# frozen_string_literal: true

RSpec.describe "bundle install" do
  describe "with bundler dependencies" do
    before(:each) do
      build_repo2 do
        build_gem "rails", "3.0" do |s|
          s.add_dependency "bundler", ">= 0.9.0"
        end
        build_gem "bundler", "0.9.1"
        build_gem "bundler", Bundler::VERSION
      end
    end

    it "are forced to the current bundler version" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "rails", "3.0"
      G

      expect(the_bundle).to include_gems "bundler #{Bundler::VERSION}"
    end

    it "are forced to the current bundler version even if not already present" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
      expect(the_bundle).to include_gems "bundler #{Bundler::VERSION}"
    end

    it "causes a conflict if explicitly requesting a different version of bundler" do
      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo2"
        gem "rails", "3.0"
        gem "bundler", "0.9.1"
      G

      nice_error = <<~E.strip
        Could not find compatible versions

        Because the current Bundler version (#{Bundler::VERSION}) does not satisfy bundler = 0.9.1
          and Gemfile depends on bundler = 0.9.1,
          version solving has failed.

        Your bundle requires a different version of Bundler than the one you're running.
        Install the necessary version with `gem install bundler:0.9.1` and rerun bundler using `bundle _0.9.1_ install`
        E
      expect(err).to include(nice_error)
    end

    it "causes a conflict if explicitly requesting a non matching requirement on bundler" do
      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo2"
        gem "rails", "3.0"
        gem "bundler", "~> 0.8"
      G

      nice_error = <<~E.strip
        Could not find compatible versions

        Because rails >= 3.0 depends on bundler >= 0.9.0
          and the current Bundler version (#{Bundler::VERSION}) does not satisfy bundler >= 0.9.0, < 1.A,
          rails >= 3.0 requires bundler >= 1.A.
        So, because Gemfile depends on rails = 3.0
          and Gemfile depends on bundler ~> 0.8,
          version solving has failed.

        Your bundle requires a different version of Bundler than the one you're running.
        Install the necessary version with `gem install bundler:0.9.1` and rerun bundler using `bundle _0.9.1_ install`
        E
      expect(err).to include(nice_error)
    end

    it "causes a conflict if explicitly requesting a version of bundler that doesn't exist" do
      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo2"
        gem "rails", "3.0"
        gem "bundler", "0.9.2"
      G

      nice_error = <<~E.strip
        Could not find compatible versions

        Because the current Bundler version (#{Bundler::VERSION}) does not satisfy bundler = 0.9.2
          and Gemfile depends on bundler = 0.9.2,
          version solving has failed.

        Your bundle requires a different version of Bundler than the one you're running, and that version could not be found.
        E
      expect(err).to include(nice_error)
    end

    it "works for gems with multiple versions in its dependencies" do
      build_repo2 do
        build_gem "multiple_versioned_deps" do |s|
          s.add_dependency "weakling", ">= 0.0.1", "< 0.1"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"

        gem "multiple_versioned_deps"
      G

      install_gemfile <<-G
        source "https://gem.repo2"

        gem "multiple_versioned_deps"
        gem "myrack"
      G

      expect(the_bundle).to include_gems "multiple_versioned_deps 1.0.0"
    end

    it "includes bundler in the bundle when it's a child dependency" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "rails", "3.0"
      G

      run "begin; gem 'bundler'; puts 'WIN'; rescue Gem::LoadError; puts 'FAIL'; end"
      expect(out).to eq("WIN")
    end

    it "allows gem 'bundler' when Bundler is not in the Gemfile or its dependencies" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"
      G

      run "begin; gem 'bundler'; puts 'WIN'; rescue Gem::LoadError => e; puts e.backtrace; end"
      expect(out).to eq("WIN")
    end

    it "causes a conflict if child dependencies conflict" do
      bundle "config set force_ruby_platform true"

      update_repo2 do
        build_gem "rails_pinned_to_old_activesupport" do |s|
          s.add_dependency "activesupport", "= 1.2.3"
        end
      end

      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo2"
        gem "activemerchant"
        gem "rails_pinned_to_old_activesupport"
      G

      nice_error = <<~E.strip
        Could not find compatible versions

        Because every version of rails_pinned_to_old_activesupport depends on activesupport = 1.2.3
          and every version of activemerchant depends on activesupport >= 2.0.0,
          every version of rails_pinned_to_old_activesupport is incompatible with activemerchant >= 0.
        So, because Gemfile depends on activemerchant >= 0
          and Gemfile depends on rails_pinned_to_old_activesupport >= 0,
          version solving has failed.
      E
      expect(err).to include(nice_error)
    end

    it "causes a conflict if a child dependency conflicts with the Gemfile" do
      bundle "config set force_ruby_platform true"

      update_repo2 do
        build_gem "rails_pinned_to_old_activesupport" do |s|
          s.add_dependency "activesupport", "= 1.2.3"
        end
      end

      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo2"
        gem "rails_pinned_to_old_activesupport"
        gem "activesupport", "2.3.5"
      G

      nice_error = <<~E.strip
        Could not find compatible versions

        Because every version of rails_pinned_to_old_activesupport depends on activesupport = 1.2.3
          and Gemfile depends on rails_pinned_to_old_activesupport >= 0,
          activesupport = 1.2.3 is required.
        So, because Gemfile depends on activesupport = 2.3.5,
          version solving has failed.
      E
      expect(err).to include(nice_error)
    end

    it "does not cause a conflict if new dependencies in the Gemfile require older dependencies than the lockfile" do
      update_repo2 do
        build_gem "rails_pinned_to_old_activesupport" do |s|
          s.add_dependency "activesupport", "= 1.2.3"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem 'rails', "2.3.2"
      G

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "rails_pinned_to_old_activesupport"
      G

      expect(out).to include("Installing activesupport 1.2.3 (was 2.3.2)")
      expect(err).to be_empty
    end

    it "prints the previous version when switching to a previously downloaded gem" do
      build_repo4 do
        build_gem "rails", "7.0.3"
        build_gem "rails", "7.0.4"
      end

      bundle "config set path.system true"

      install_gemfile <<-G
        source "https://gem.repo4"
        gem 'rails', "7.0.4"
      G

      install_gemfile <<-G
        source "https://gem.repo4"
        gem 'rails', "7.0.3"
      G

      install_gemfile <<-G
        source "https://gem.repo4"
        gem 'rails', "7.0.4"
      G

      expect(out).to include("Using rails 7.0.4 (was 7.0.3)")
      expect(err).to be_empty
    end

    it "can install dependencies with newer bundler version with system gems" do
      bundle "config set path.system true"

      system_gems "bundler-99999999.99.1"

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "rails", "3.0"
      G

      bundle "check"
      expect(out).to include("The Gemfile's dependencies are satisfied")
    end

    it "can install dependencies with newer bundler version with a local path" do
      bundle "config set path .bundle"

      system_gems "bundler-99999999.99.1"

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "rails", "3.0"
      G

      bundle "check"
      expect(out).to include("The Gemfile's dependencies are satisfied")
    end
  end
end
