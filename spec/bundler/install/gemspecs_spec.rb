# encoding: utf-8
# frozen_string_literal: true

RSpec.describe "bundle install" do
  describe "when a gem has a YAML gemspec" do
    before :each do
      build_repo2 do
        build_gem "yaml_spec", :gemspec => :yaml
      end
    end

    it "still installs correctly" do
      gemfile <<-G
        source "file://#{gem_repo2}"
        gem "yaml_spec"
      G
      bundle :install
      expect(err).to lack_errors
    end

    it "still installs correctly when using path" do
      build_lib "yaml_spec", :gemspec => :yaml

      install_gemfile <<-G
        gem 'yaml_spec', :path => "#{lib_path("yaml_spec-1.0")}"
      G
      expect(err).to lack_errors
    end
  end

  it "should use gemspecs in the system cache when available" do
    gemfile <<-G
      source "http://localtestserver.gem"
      gem 'rack'
    G

    FileUtils.mkdir_p "#{default_bundle_path}/specifications"
    File.open("#{default_bundle_path}/specifications/rack-1.0.0.gemspec", "w+") do |f|
      spec = Gem::Specification.new do |s|
        s.name = "rack"
        s.version = "1.0.0"
        s.add_runtime_dependency "activesupport", "2.3.2"
      end
      f.write spec.to_ruby
    end
    bundle :install, :artifice => "endpoint_marshal_fail" # force gemspec load
    expect(the_bundle).to include_gems "activesupport 2.3.2"
  end

  it "does not hang when gemspec has incompatible encoding" do
    create_file "foo.gemspec", <<-G
      Gem::Specification.new do |gem|
        gem.name = "pry-byebug"
        gem.version = "3.4.2"
        gem.author = "David Rodriguez"
        gem.summary = "Good stuff"
      end
    G

    install_gemfile <<-G, :env => { "LANG" => "C" }
      gemspec
    G

    expect(out).to include("Bundle complete!")
  end

  it "reads gemspecs respecting their encoding" do
    skip "Unicode is not supported on Ruby 1.x without extra work" if RUBY_VERSION < "2.0"

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
      gemspec
    G

    expect(out).to include("Bundle complete!")
  end

  context "when ruby version is specified in gemspec and gemfile" do
    it "installs when patch level is not specified and the version matches" do
      build_lib("foo", :path => bundled_app) do |s|
        s.required_ruby_version = "~> #{RUBY_VERSION}.0"
      end

      install_gemfile <<-G
        ruby '#{RUBY_VERSION}', :engine_version => '#{RUBY_VERSION}', :engine => 'ruby'
        gemspec
      G
      expect(the_bundle).to include_gems "foo 1.0"
    end

    it "installs when patch level is specified and the version still matches the current version",
      :if => RUBY_PATCHLEVEL >= 0 do
      build_lib("foo", :path => bundled_app) do |s|
        s.required_ruby_version = "#{RUBY_VERSION}.#{RUBY_PATCHLEVEL}"
      end

      install_gemfile <<-G
        ruby '#{RUBY_VERSION}', :engine_version => '#{RUBY_VERSION}', :engine => 'ruby', :patchlevel => '#{RUBY_PATCHLEVEL}'
        gemspec
      G
      expect(the_bundle).to include_gems "foo 1.0"
    end

    it "fails and complains about patchlevel on patchlevel mismatch",
      :if => RUBY_PATCHLEVEL >= 0 do
      patchlevel = RUBY_PATCHLEVEL.to_i + 1
      build_lib("foo", :path => bundled_app) do |s|
        s.required_ruby_version = "#{RUBY_VERSION}.#{patchlevel}"
      end

      install_gemfile <<-G
        ruby '#{RUBY_VERSION}', :engine_version => '#{RUBY_VERSION}', :engine => 'ruby', :patchlevel => '#{patchlevel}'
        gemspec
      G

      expect(out).to include("Ruby patchlevel")
      expect(out).to include("but your Gemfile specified")
      expect(exitstatus).to eq(18) if exitstatus
    end

    it "fails and complains about version on version mismatch" do
      version = Gem::Requirement.create(RUBY_VERSION).requirements.first.last.bump.version

      build_lib("foo", :path => bundled_app) do |s|
        s.required_ruby_version = version
      end

      install_gemfile <<-G
        ruby '#{version}', :engine_version => '#{version}', :engine => 'ruby'
        gemspec
      G

      expect(out).to include("Ruby version")
      expect(out).to include("but your Gemfile specified")
      expect(exitstatus).to eq(18) if exitstatus
    end
  end
end
