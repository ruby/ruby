# frozen_string_literal: true

RSpec.describe "bundle install" do
  describe "when a gem has a YAML gemspec" do
    before :each do
      build_repo2 do
        build_gem "yaml_spec", gemspec: :yaml
      end
    end

    it "still installs correctly" do
      gemfile <<-G
        source "https://gem.repo2"
        gem "yaml_spec"
      G
      bundle :install
      expect(err).to be_empty
    end

    it "still installs correctly when using path" do
      build_lib "yaml_spec", gemspec: :yaml

      install_gemfile <<-G
        source "https://gem.repo1"
        gem 'yaml_spec', :path => "#{lib_path("yaml_spec-1.0")}"
      G
      expect(err).to be_empty
    end
  end

  it "should use gemspecs in the system cache when available" do
    gemfile <<-G
      source "http://localtestserver.gem"
      gem 'myrack'
    G

    system_gems "myrack-1.0.0", path: default_bundle_path

    FileUtils.mkdir_p "#{default_bundle_path}/specifications"
    File.open("#{default_bundle_path}/specifications/myrack-1.0.0.gemspec", "w+") do |f|
      spec = Gem::Specification.new do |s|
        s.name = "myrack"
        s.version = "1.0.0"
        s.add_dependency "activesupport", "2.3.2"
      end
      f.write spec.to_ruby
    end
    bundle :install, artifice: "endpoint_marshal_fail" # force gemspec load
    expect(the_bundle).to include_gems "myrack 1.0.0", "activesupport 2.3.2"
  end

  it "does not hang when gemspec has incompatible encoding" do
    create_file("foo.gemspec", <<-G)
      Gem::Specification.new do |gem|
        gem.name = "pry-byebug"
        gem.version = "3.4.2"
        gem.author = "David Rodríguez"
        gem.summary = "Good stuff"
      end
    G

    install_gemfile <<-G, env: { "LANG" => "C" }
      source "https://gem.repo1"
      gemspec
    G

    expect(out).to include("Bundle complete!")
  end

  it "reads gemspecs respecting their encoding" do
    create_file "version.rb", <<-RUBY
      module Persistent💎
        VERSION = "0.0.1"
      end
    RUBY

    create_file "persistent-dmnd.gemspec", <<-G
      require_relative "version"

      Gem::Specification.new do |gem|
        gem.name = "persistent-dmnd"
        gem.version = Persistent💎::VERSION
        gem.author = "Ivo Anjo"
        gem.summary = "Unscratchable stuff"
      end
    G

    install_gemfile <<-G
      source "https://gem.repo1"
      gemspec
    G

    expect(out).to include("Bundle complete!")
  end

  context "when ruby version is specified in gemspec and gemfile" do
    it "installs when patch level is not specified and the version matches",
      if: RUBY_PATCHLEVEL >= 0 do
      build_lib("foo", path: bundled_app) do |s|
        s.required_ruby_version = "~> #{RUBY_VERSION}.0"
      end

      install_gemfile <<-G
        ruby '#{RUBY_VERSION}', :engine_version => '#{RUBY_VERSION}', :engine => 'ruby'
        source "https://gem.repo1"
        gemspec
      G
      expect(the_bundle).to include_gems "foo 1.0"
    end

    it "installs when patch level is specified and the version still matches the current version",
      if: RUBY_PATCHLEVEL >= 0 do
      build_lib("foo", path: bundled_app) do |s|
        s.required_ruby_version = "#{RUBY_VERSION}.#{RUBY_PATCHLEVEL}"
      end

      install_gemfile <<-G, raise_on_error: false
        ruby '#{RUBY_VERSION}', :engine_version => '#{RUBY_VERSION}', :engine => 'ruby', :patchlevel => '#{RUBY_PATCHLEVEL}'
        source "https://gem.repo1"
        gemspec
      G
      expect(the_bundle).to include_gems "foo 1.0"
    end

    it "fails and complains about patchlevel on patchlevel mismatch",
      if: RUBY_PATCHLEVEL >= 0 do
      patchlevel = RUBY_PATCHLEVEL.to_i + 1
      build_lib("foo", path: bundled_app) do |s|
        s.required_ruby_version = "#{RUBY_VERSION}.#{patchlevel}"
      end

      install_gemfile <<-G, raise_on_error: false
        ruby '#{RUBY_VERSION}', :engine_version => '#{RUBY_VERSION}', :engine => 'ruby', :patchlevel => '#{patchlevel}'
        source "https://gem.repo1"
        gemspec
      G

      expect(err).to include("Ruby patchlevel")
      expect(err).to include("but your Gemfile specified")
      expect(exitstatus).to eq(18)
    end

    it "fails and complains about version on version mismatch" do
      version = Gem::Requirement.create(RUBY_VERSION).requirements.first.last.bump.version

      build_lib("foo", path: bundled_app) do |s|
        s.required_ruby_version = version
      end

      install_gemfile <<-G, raise_on_error: false
        ruby '#{version}', :engine_version => '#{version}', :engine => 'ruby'
        source "https://gem.repo1"
        gemspec
      G

      expect(err).to include("Ruby version")
      expect(err).to include("but your Gemfile specified")
      expect(exitstatus).to eq(18)
    end

    it "validates gemspecs just once when everything installed and lockfile up to date" do
      build_lib "foo"

      install_gemfile <<-G
        source "https://gem.repo1"
        gemspec path: "#{lib_path("foo-1.0")}"

        module Monkey
          def validate(spec)
            puts "Validate called on \#{spec.full_name}"
          end
        end
        Bundler.rubygems.extend(Monkey)
      G

      bundle "install"

      expect(out).to include("Validate called on foo-1.0").once
    end
  end
end
