# frozen_string_literal: true
require "spec_helper"

RSpec.describe "bundle add" do
  before :each do
    build_repo2 do
      build_gem "foo", "1.1"
      build_gem "foo", "2.0"
      build_gem "baz", "1.2.3"
      build_gem "bar", "0.12.3"
      build_gem "cat", "0.12.3.pre"
      build_gem "dog", "1.1.3.pre"
    end

    install_gemfile <<-G
      source "file://#{gem_repo2}"
      gem "weakling", "~> 0.0.1"
    G
  end

  describe "without version specified" do
    it "version requirement becomes ~> major.minor.patch when resolved version is < 1.0" do
      bundle "add 'bar'"
      expect(bundled_app("Gemfile").read).to match(/gem "bar", "~> 0.12.3"/)
      expect(the_bundle).to include_gems "bar 0.12.3"
    end

    it "version requirement becomes ~> major.minor when resolved version is > 1.0" do
      bundle "add 'baz'"
      expect(bundled_app("Gemfile").read).to match(/gem "baz", "~> 1.2"/)
      expect(the_bundle).to include_gems "baz 1.2.3"
    end

    it "version requirement becomes ~> major.minor.patch.pre when resolved version is < 1.0" do
      bundle "add 'cat'"
      expect(bundled_app("Gemfile").read).to match(/gem "cat", "~> 0.12.3.pre"/)
      expect(the_bundle).to include_gems "cat 0.12.3.pre"
    end

    it "version requirement becomes ~> major.minor.pre when resolved version is > 1.0.pre" do
      bundle "add 'dog'"
      expect(bundled_app("Gemfile").read).to match(/gem "dog", "~> 1.1.pre"/)
      expect(the_bundle).to include_gems "dog 1.1.3.pre"
    end
  end

  describe "with --version" do
    it "adds dependency of specified version and runs install" do
      bundle "add 'foo' --version='~> 1.0'"
      expect(bundled_app("Gemfile").read).to match(/gem "foo", "~> 1.0"/)
      expect(the_bundle).to include_gems "foo 1.1"
    end

    it "adds multiple version constraints when specified" do
      bundle "add 'foo' --version='< 3.0, > 1.1'"
      expect(bundled_app("Gemfile").read).to match(/gem "foo", "< 3.0", "> 1.1"/)
      expect(the_bundle).to include_gems "foo 2.0"
    end
  end

  describe "with --group" do
    it "adds dependency for the specified group" do
      bundle "add 'foo' --group='development'"
      expect(bundled_app("Gemfile").read).to match(/gem "foo", "~> 2.0", :group => \[:development\]/)
      expect(the_bundle).to include_gems "foo 2.0"
    end

    it "adds dependency to more than one group" do
      bundle "add 'foo' --group='development, test'"
      expect(bundled_app("Gemfile").read).to match(/gem "foo", "~> 2.0", :groups => \[:development, :test\]/)
      expect(the_bundle).to include_gems "foo 2.0"
    end
  end

  describe "with --source" do
    it "adds dependency with specified source" do
      bundle "add 'foo' --source='file://#{gem_repo2}'"
      expect(bundled_app("Gemfile").read).to match(%r{gem "foo", "~> 2.0", :source => "file:\/\/#{gem_repo2}"})
      expect(the_bundle).to include_gems "foo 2.0"
    end
  end

  it "using combination of short form options works like long form" do
    bundle "add 'foo' -s='file://#{gem_repo2}' -g='development' -v='~>1.0'"
    expect(bundled_app("Gemfile").read).to match(%r{gem "foo", "~> 1.0", :group => \[:development\], :source => "file:\/\/#{gem_repo2}"})
    expect(the_bundle).to include_gems "foo 1.1"
  end

  it "shows error message when version is not formatted correctly" do
    bundle "add 'foo' -v='~>1 . 0'"
    expect(out).to match("Invalid gem requirement pattern '~>1 . 0'")
  end

  it "shows error message when gem cannot be found" do
    bundle "add 'werk_it'"
    expect(out).to match("Could not find gem 'werk_it' in any of the gem sources listed in your Gemfile.")

    bundle "add 'werk_it' -s='file://#{gem_repo2}'"
    expect(out).to match("Could not find gem 'werk_it' in rubygems repository")
  end

  it "shows error message when source cannot be reached" do
    bundle "add 'baz' --source='http://badhostasdf'"
    expect(out).to include("Could not reach host badhostasdf. Check your network connection and try again.")

    bundle "add 'baz' --source='file://does/not/exist'"
    expect(out).to include("Could not fetch specs from file://does/not/exist/")
  end
end
