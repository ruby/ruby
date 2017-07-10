# frozen_string_literal: true
require "spec_helper"

describe "bundle_ruby" do
  context "without patchlevel" do
    it "returns the ruby version" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        ruby "1.9.3", :engine => 'ruby', :engine_version => '1.9.3'

        gem "foo"
      G

      bundle_ruby

      expect(out).to include("ruby 1.9.3")
    end

    it "engine defaults to MRI" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        ruby "1.9.3"

        gem "foo"
      G

      bundle_ruby

      expect(out).to include("ruby 1.9.3")
    end

    it "handles jruby" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        ruby "1.8.7", :engine => 'jruby', :engine_version => '1.6.5'

        gem "foo"
      G

      bundle_ruby

      expect(out).to include("ruby 1.8.7 (jruby 1.6.5)")
    end

    it "handles rbx" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        ruby "1.8.7", :engine => 'rbx', :engine_version => '1.2.4'

        gem "foo"
      G

      bundle_ruby

      expect(out).to include("ruby 1.8.7 (rbx 1.2.4)")
    end

    it "raises an error if engine is used but engine version is not" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        ruby "1.8.7", :engine => 'rbx'

        gem "foo"
      G

      bundle_ruby
      expect(exitstatus).not_to eq(0) if exitstatus

      bundle_ruby
      expect(out).to include("Please define :engine_version")
    end

    it "raises an error if engine_version is used but engine is not" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        ruby "1.8.7", :engine_version => '1.2.4'

        gem "foo"
      G

      bundle_ruby
      expect(exitstatus).not_to eq(0) if exitstatus

      bundle_ruby
      expect(out).to include("Please define :engine")
    end

    it "raises an error if engine version doesn't match ruby version for MRI" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        ruby "1.8.7", :engine => 'ruby', :engine_version => '1.2.4'

        gem "foo"
      G

      bundle_ruby
      expect(exitstatus).not_to eq(0) if exitstatus

      bundle_ruby
      expect(out).to include("ruby_version must match the :engine_version for MRI")
    end

    it "should print if no ruby version is specified" do
      gemfile <<-G
        source "file://#{gem_repo1}"

        gem "foo"
      G

      bundle_ruby

      expect(out).to include("No ruby version specified")
    end
  end

  context "when using patchlevel" do
    it "returns the ruby version" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        ruby "1.9.3", :patchlevel => '429', :engine => 'ruby', :engine_version => '1.9.3'

        gem "foo"
      G

      bundle_ruby

      expect(out).to include("ruby 1.9.3p429")
    end

    it "handles an engine" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        ruby "1.9.3", :patchlevel => '392', :engine => 'jruby', :engine_version => '1.7.4'

        gem "foo"
      G

      bundle_ruby

      expect(out).to include("ruby 1.9.3p392 (jruby 1.7.4)")
    end
  end
end
