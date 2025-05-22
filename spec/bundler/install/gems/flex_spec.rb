# frozen_string_literal: true

RSpec.describe "bundle flex_install" do
  it "installs the gems as expected" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem 'myrack'
    G

    expect(the_bundle).to include_gems "myrack 1.0.0"
    expect(the_bundle).to be_locked
  end

  it "installs even when the lockfile is invalid" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem 'myrack'
    G

    expect(the_bundle).to include_gems "myrack 1.0.0"
    expect(the_bundle).to be_locked

    gemfile <<-G
      source "https://gem.repo1"
      gem 'myrack', '1.0'
    G

    bundle :install
    expect(the_bundle).to include_gems "myrack 1.0.0"
    expect(the_bundle).to be_locked
  end

  it "keeps child dependencies at the same version" do
    build_repo2

    install_gemfile <<-G
      source "https://gem.repo2"
      gem "myrack-obama"
    G

    expect(the_bundle).to include_gems "myrack 1.0.0", "myrack-obama 1.0.0"

    update_repo2
    install_gemfile <<-G
      source "https://gem.repo2"
      gem "myrack-obama", "1.0"
    G

    expect(the_bundle).to include_gems "myrack 1.0.0", "myrack-obama 1.0.0"
  end

  describe "adding new gems" do
    it "installs added gems without updating previously installed gems" do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem 'myrack'
      G

      update_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem 'myrack'
        gem 'activesupport', '2.3.5'
      G

      expect(the_bundle).to include_gems "myrack 1.0.0", "activesupport 2.3.5"
    end

    it "keeps child dependencies pinned" do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack-obama"
      G

      update_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack-obama"
        gem "thin"
      G

      expect(the_bundle).to include_gems "myrack 1.0.0", "myrack-obama 1.0", "thin 1.0"
    end
  end

  describe "removing gems" do
    it "removes gems without changing the versions of remaining gems" do
      build_repo2
      install_gemfile <<-G
        source "https://gem.repo2"
        gem 'myrack'
        gem 'activesupport', '2.3.5'
      G

      update_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem 'myrack'
      G

      expect(the_bundle).to include_gems "myrack 1.0.0"
      expect(the_bundle).not_to include_gems "activesupport 2.3.5"

      install_gemfile <<-G
        source "https://gem.repo2"
        gem 'myrack'
        gem 'activesupport', '2.3.2'
      G

      expect(the_bundle).to include_gems "myrack 1.0.0", "activesupport 2.3.2"
    end

    it "removes top level dependencies when removed from the Gemfile while leaving other dependencies intact" do
      build_repo2
      install_gemfile <<-G
        source "https://gem.repo2"
        gem 'myrack'
        gem 'activesupport', '2.3.5'
      G

      update_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem 'myrack'
      G

      expect(the_bundle).not_to include_gems "activesupport 2.3.5"
    end

    it "removes child dependencies" do
      build_repo2
      install_gemfile <<-G
        source "https://gem.repo2"
        gem 'myrack-obama'
        gem 'activesupport'
      G

      expect(the_bundle).to include_gems "myrack 1.0.0", "myrack-obama 1.0.0", "activesupport 2.3.5"

      update_repo2
      install_gemfile <<-G
        source "https://gem.repo2"
        gem 'activesupport'
      G

      expect(the_bundle).to include_gems "activesupport 2.3.5"
      expect(the_bundle).not_to include_gems "myrack-obama", "myrack"
    end
  end

  describe "when running bundle install and Gemfile conflicts with lockfile" do
    before(:each) do
      build_repo2
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack_middleware"
      G

      expect(the_bundle).to include_gems "myrack_middleware 1.0", "myrack 0.9.1"

      build_repo2 do
        build_gem "myrack-obama", "2.0" do |s|
          s.add_dependency "myrack", "=1.2"
        end
        build_gem "myrack_middleware", "2.0" do |s|
          s.add_dependency "myrack", ">=1.0"
        end
      end

      gemfile <<-G
        source "https://gem.repo2"
        gem "myrack-obama", "2.0"
        gem "myrack_middleware"
      G
    end

    it "does not install gems whose dependencies are not met" do
      bundle :install, raise_on_error: false
      ruby <<-RUBY, raise_on_error: false
        require 'bundler/setup'
      RUBY
      expect(err).to match(/could not find gem 'myrack-obama/i)
    end

    it "discards the locked gems when the Gemfile requires different versions than the lock" do
      bundle "config set force_ruby_platform true"

      nice_error = <<~E.strip
        Could not find compatible versions

        Because myrack-obama >= 2.0 depends on myrack = 1.2
          and myrack = 1.2 could not be found in rubygems repository https://gem.repo2/ or installed locally,
          myrack-obama >= 2.0 cannot be used.
        So, because Gemfile depends on myrack-obama = 2.0,
          version solving has failed.
      E

      bundle :install, retry: 0, raise_on_error: false
      expect(err).to end_with(nice_error)
    end

    it "does not include conflicts with a single requirement tree, because that can't possibly be a conflict" do
      bundle "config set force_ruby_platform true"

      bad_error = <<~E.strip
        Bundler could not find compatible versions for gem "myrack-obama":
          In Gemfile:
            myrack-obama (= 2.0)
      E

      bundle "update myrack_middleware", retry: 0, raise_on_error: false
      expect(err).not_to end_with(bad_error)
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
        source "https://gem.repo4"
        gem "jekyll-feed", "~> 0.12"
      G

      gemfile <<-G
        source "https://gem.repo4"
        gem "github-pages", "~> 226"
        gem "jekyll-feed", "~> 0.12"
      G
    end

    it "discards the conflicting lockfile information and resolves properly" do
      bundle :update, raise_on_error: false, all: true
      expect(err).to be_empty
    end
  end

  describe "subtler cases" do
    before :each do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "myrack-obama"
      G

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", "0.9.1"
        gem "myrack-obama"
      G
    end

    it "should work when you install" do
      bundle "install"

      checksums = checksums_section_when_enabled do |c|
        c.checksum gem_repo1, "myrack", "0.9.1"
        c.checksum gem_repo1, "myrack-obama", "1.0"
      end

      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo1/
          specs:
            myrack (0.9.1)
            myrack-obama (1.0)
              myrack

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          myrack (= 0.9.1)
          myrack-obama
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end

    it "should work when you update" do
      bundle "update myrack"

      checksums = checksums_section_when_enabled do |c|
        c.checksum gem_repo1, "myrack", "0.9.1"
        c.checksum gem_repo1, "myrack-obama", "1.0"
      end

      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo1/
          specs:
            myrack (0.9.1)
            myrack-obama (1.0)
              myrack

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          myrack (= 0.9.1)
          myrack-obama
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end
  end

  describe "when adding a new source" do
    it "updates the lockfile" do
      build_repo2
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      install_gemfile <<-G
        source "https://gem.repo1"
        source "https://gem.repo2" do
        end
        gem "myrack"
      G

      checksums = checksums_section_when_enabled do |c|
        c.checksum gem_repo1, "myrack", "1.0.0"
      end

      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo1/
          specs:
            myrack (1.0.0)

        GEM
          remote: https://gem.repo2/
          specs:

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          myrack
        #{checksums}
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
          s.add_dependency "myrack", ">= 1.0.0"
        end

        build_gem "myrack", "1.1.0"
        build_gem "rails", "3.0.0.rc4" do |s|
          s.add_dependency "myrack", "~> 1.1.0"
        end

        build_gem "myrack", "1.2.1"
        build_gem "rails", "3.0.0" do |s|
          s.add_dependency "myrack", "~> 1.2.1"
        end
      end
    end

    it "resolves them" do
      # install Rails 3.0.0.rc
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "rails", "3.0.0.rc4"
        gem "capybara", "0.3.9"
      G

      # upgrade Rails to 3.0.0 and then install again
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "rails", "3.0.0"
        gem "capybara", "0.3.9"
      G
      expect(err).to be_empty
    end
  end
end
