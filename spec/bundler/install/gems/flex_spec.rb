# frozen_string_literal: true

RSpec.describe "bundle flex_install" do
  it "installs the gems as expected" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem 'rack'
    G

    expect(the_bundle).to include_gems "rack 1.0.0"
    expect(the_bundle).to be_locked
  end

  it "installs even when the lockfile is invalid" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem 'rack'
    G

    expect(the_bundle).to include_gems "rack 1.0.0"
    expect(the_bundle).to be_locked

    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem 'rack', '1.0'
    G

    bundle :install
    expect(the_bundle).to include_gems "rack 1.0.0"
    expect(the_bundle).to be_locked
  end

  it "keeps child dependencies at the same version" do
    build_repo2

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
      gem "rack-obama"
    G

    expect(the_bundle).to include_gems "rack 1.0.0", "rack-obama 1.0.0"

    update_repo2
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
      gem "rack-obama", "1.0"
    G

    expect(the_bundle).to include_gems "rack 1.0.0", "rack-obama 1.0.0"
  end

  describe "adding new gems" do
    it "installs added gems without updating previously installed gems" do
      build_repo2

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem 'rack'
      G

      update_repo2

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem 'rack'
        gem 'activesupport', '2.3.5'
      G

      expect(the_bundle).to include_gems "rack 1.0.0", "activesupport 2.3.5"
    end

    it "keeps child dependencies pinned" do
      build_repo2

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack-obama"
      G

      update_repo2

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack-obama"
        gem "thin"
      G

      expect(the_bundle).to include_gems "rack 1.0.0", "rack-obama 1.0", "thin 1.0"
    end
  end

  describe "removing gems" do
    it "removes gems without changing the versions of remaining gems" do
      build_repo2
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem 'rack'
        gem 'activesupport', '2.3.5'
      G

      update_repo2

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem 'rack'
      G

      expect(the_bundle).to include_gems "rack 1.0.0"
      expect(the_bundle).not_to include_gems "activesupport 2.3.5"

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem 'rack'
        gem 'activesupport', '2.3.2'
      G

      expect(the_bundle).to include_gems "rack 1.0.0", "activesupport 2.3.2"
    end

    it "removes top level dependencies when removed from the Gemfile while leaving other dependencies intact" do
      build_repo2
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem 'rack'
        gem 'activesupport', '2.3.5'
      G

      update_repo2

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem 'rack'
      G

      expect(the_bundle).not_to include_gems "activesupport 2.3.5"
    end

    it "removes child dependencies" do
      build_repo2
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem 'rack-obama'
        gem 'activesupport'
      G

      expect(the_bundle).to include_gems "rack 1.0.0", "rack-obama 1.0.0", "activesupport 2.3.5"

      update_repo2
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem 'activesupport'
      G

      expect(the_bundle).to include_gems "activesupport 2.3.5"
      expect(the_bundle).not_to include_gems "rack-obama", "rack"
    end
  end

  describe "when running bundle install and Gemfile conflicts with lockfile" do
    before(:each) do
      build_repo2
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack_middleware"
      G

      expect(the_bundle).to include_gems "rack_middleware 1.0", "rack 0.9.1"

      build_repo2 do
        build_gem "rack-obama", "2.0" do |s|
          s.add_dependency "rack", "=1.2"
        end
        build_gem "rack_middleware", "2.0" do |s|
          s.add_dependency "rack", ">=1.0"
        end
      end

      gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack-obama", "2.0"
        gem "rack_middleware"
      G
    end

    it "does not install gems whose dependencies are not met" do
      bundle :install, :raise_on_error => false
      ruby <<-RUBY, :raise_on_error => false
        require 'bundler/setup'
      RUBY
      expect(err).to match(/could not find gem 'rack-obama/i)
    end

    it "suggests deleting the Gemfile.lock file when the Gemfile requires different versions than the lock" do
      bundle "config set force_ruby_platform true"

      nice_error = <<-E.strip.gsub(/^ {8}/, "")
        Bundler could not find compatible versions for gem "rack":
          In snapshot (Gemfile.lock):
            rack (= 0.9.1)

          In Gemfile:
            rack-obama (= 2.0) was resolved to 2.0, which depends on
              rack (= 1.2)

            rack_middleware was resolved to 1.0, which depends on
              rack (= 0.9.1)

        Deleting your Gemfile.lock file and running `bundle install` will rebuild your snapshot from scratch, using only
        the gems in your Gemfile, which may resolve the conflict.
      E

      bundle :install, :retry => 0, :raise_on_error => false
      expect(err).to end_with(nice_error)
    end
  end

  describe "when running bundle update and Gemfile conflicts with lockfile" do
    before(:each) do
      build_repo4 do
        build_gem "jekyll-feed", "0.16.0"
        build_gem "jekyll-feed", "0.15.1"

        build_gem "github-pages", "226" do |s|
          s.add_dependency "jekyll-feed", "0.15.1"
        end
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
        gem "jekyll-feed", "~> 0.12"
      G

      lockfile <<-L
        GEM
          remote: #{file_uri_for(gem_repo4)}/
          specs:
            jekyll-feed (0.16.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          jekyll-feed

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
        gem "github-pages", "~> 226"
        gem "jekyll-feed", "~> 0.12"
      G
    end

    it "suggests deleting the Gemfile.lock file when the Gemfile requires different versions than the lock" do
      nice_error = <<-E.strip.gsub(/^ {8}/, "")
        Bundler could not find compatible versions for gem "jekyll-feed":
          In snapshot (Gemfile.lock):
            jekyll-feed (>= 0.16.0)

          In Gemfile:
            jekyll-feed (~> 0.12)

            github-pages (~> 226) was resolved to 226, which depends on
              jekyll-feed (= 0.15.1)

        Deleting your Gemfile.lock file and running `bundle install` will rebuild your snapshot from scratch, using only
        the gems in your Gemfile, which may resolve the conflict.
      E

      bundle :update, :raise_on_error => false
      expect(err).to end_with(nice_error)
    end
  end

  describe "subtler cases" do
    before :each do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
        gem "rack-obama"
      G

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", "0.9.1"
        gem "rack-obama"
      G
    end

    it "should work when you install" do
      bundle "install"

      expect(lockfile).to eq <<~L
        GEM
          remote: #{file_uri_for(gem_repo1)}/
          specs:
            rack (0.9.1)
            rack-obama (1.0)
              rack

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          rack (= 0.9.1)
          rack-obama

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end

    it "should work when you update" do
      bundle "update rack"
    end
  end

  describe "when adding a new source" do
    it "updates the lockfile" do
      build_repo2
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        source "#{file_uri_for(gem_repo2)}" do
        end
        gem "rack"
      G

      expect(lockfile).to eq <<~L
        GEM
          remote: #{file_uri_for(gem_repo1)}/
          specs:
            rack (1.0.0)

        GEM
          remote: #{file_uri_for(gem_repo2)}/
          specs:

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          rack

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end
  end

  # This was written to test github issue #636
  describe "when a locked child dependency conflicts" do
    before(:each) do
      build_repo2 do
        build_gem "capybara", "0.3.9" do |s|
          s.add_dependency "rack", ">= 1.0.0"
        end

        build_gem "rack", "1.1.0"
        build_gem "rails", "3.0.0.rc4" do |s|
          s.add_dependency "rack", "~> 1.1.0"
        end

        build_gem "rack", "1.2.1"
        build_gem "rails", "3.0.0" do |s|
          s.add_dependency "rack", "~> 1.2.1"
        end
      end
    end

    it "prints the correct error message" do
      # install Rails 3.0.0.rc
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rails", "3.0.0.rc4"
        gem "capybara", "0.3.9"
      G

      # upgrade Rails to 3.0.0 and then install again
      install_gemfile <<-G, :raise_on_error => false
        source "#{file_uri_for(gem_repo2)}"
        gem "rails", "3.0.0"
        gem "capybara", "0.3.9"
      G

      expect(err).to include("Gemfile.lock")
    end
  end
end
