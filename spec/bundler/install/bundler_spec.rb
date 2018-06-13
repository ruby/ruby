# frozen_string_literal: true

RSpec.describe "bundle install" do
  describe "with bundler dependencies" do
    before(:each) do
      build_repo2 do
        build_gem "rails", "3.0" do |s|
          s.add_dependency "bundler", ">= 0.9.0.pre"
        end
        build_gem "bundler", "0.9.1"
        build_gem "bundler", Bundler::VERSION
      end
    end

    it "are forced to the current bundler version" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "rails", "3.0"
      G

      expect(the_bundle).to include_gems "bundler #{Bundler::VERSION}"
    end

    it "are not added if not already present" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G
      expect(the_bundle).not_to include_gems "bundler #{Bundler::VERSION}"
    end

    it "causes a conflict if explicitly requesting a different version" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "rails", "3.0"
        gem "bundler", "0.9.2"
      G

      nice_error = <<-E.strip.gsub(/^ {8}/, "")
        Bundler could not find compatible versions for gem "bundler":
          In Gemfile:
            bundler (= 0.9.2)

          Current Bundler version:
            bundler (#{Bundler::VERSION})
        This Gemfile requires a different version of Bundler.
        Perhaps you need to update Bundler by running `gem install bundler`?

        Could not find gem 'bundler (= 0.9.2)' in any
        E
      expect(last_command.bundler_err).to include(nice_error)
    end

    it "works for gems with multiple versions in its dependencies" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"

        gem "multiple_versioned_deps"
      G

      install_gemfile <<-G
        source "file://#{gem_repo2}"

        gem "multiple_versioned_deps"
        gem "rack"
      G

      expect(the_bundle).to include_gems "multiple_versioned_deps 1.0.0"
    end

    it "includes bundler in the bundle when it's a child dependency" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "rails", "3.0"
      G

      run "begin; gem 'bundler'; puts 'WIN'; rescue Gem::LoadError; puts 'FAIL'; end"
      expect(out).to eq("WIN")
    end

    it "allows gem 'bundler' when Bundler is not in the Gemfile or its dependencies" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "rack"
      G

      run "begin; gem 'bundler'; puts 'WIN'; rescue Gem::LoadError => e; puts e.backtrace; end"
      expect(out).to eq("WIN")
    end

    it "causes a conflict if child dependencies conflict" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "activemerchant"
        gem "rails_fail"
      G

      nice_error = <<-E.strip.gsub(/^ {8}/, "")
        Bundler could not find compatible versions for gem "activesupport":
          In Gemfile:
            activemerchant was resolved to 1.0, which depends on
              activesupport (>= 2.0.0)

            rails_fail was resolved to 1.0, which depends on
              activesupport (= 1.2.3)
      E
      expect(last_command.bundler_err).to include(nice_error)
    end

    it "causes a conflict if a child dependency conflicts with the Gemfile" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "rails_fail"
        gem "activesupport", "2.3.5"
      G

      nice_error = <<-E.strip.gsub(/^ {8}/, "")
        Bundler could not find compatible versions for gem "activesupport":
          In Gemfile:
            activesupport (= 2.3.5)

            rails_fail was resolved to 1.0, which depends on
              activesupport (= 1.2.3)
      E
      expect(last_command.bundler_err).to include(nice_error)
    end

    it "can install dependencies with newer bundler version with system gems", :ruby => "> 2" do
      bundle! "config path.system true"
      install_gemfile! <<-G
        source "file://#{gem_repo2}"
        gem "rails", "3.0"
      G

      simulate_bundler_version "99999999.99.1"

      bundle! "check", :env => { "BUNDLER_SPEC_IGNORE_COMPATIBILITY_GUARD" => "1" }
      expect(out).to include("The Gemfile's dependencies are satisfied")
    end

    it "can install dependencies with newer bundler version with a local path", :ruby => "> 2" do
      bundle! "config path .bundle"
      install_gemfile! <<-G
        source "file://#{gem_repo2}"
        gem "rails", "3.0"
      G

      simulate_bundler_version "99999999.99.1"

      bundle! "check", :env => { "BUNDLER_SPEC_IGNORE_COMPATIBILITY_GUARD" => "1" }
      expect(out).to include("The Gemfile's dependencies are satisfied")
    end

    context "with allow_bundler_dependency_conflicts set" do
      before { bundle! "config allow_bundler_dependency_conflicts true" }

      it "are forced to the current bundler version with warnings when no compatible version is found" do
        build_repo4 do
          build_gem "requires_nonexistant_bundler" do |s|
            s.add_runtime_dependency "bundler", "99.99.99.99"
          end
        end

        install_gemfile! <<-G
          source "file://#{gem_repo4}"
          gem "requires_nonexistant_bundler"
        G

        expect(out).to include "requires_nonexistant_bundler (1.0) has dependency bundler (= 99.99.99.99), " \
                               "which is unsatisfied by the current bundler version #{Bundler::VERSION}, so the dependency is being ignored"

        expect(the_bundle).to include_gems "bundler #{Bundler::VERSION}", "requires_nonexistant_bundler 1.0"
      end
    end
  end
end
