# frozen_string_literal: true

RSpec.describe "bundle install with ENV conditionals" do
  describe "when just setting an ENV key as a string" do
    before :each do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        env "BUNDLER_TEST" do
          gem "rack"
        end
      G
    end

    it "excludes the gems when the ENV variable is not set" do
      bundle :install
      expect(the_bundle).not_to include_gems "rack"
    end

    it "includes the gems when the ENV variable is set" do
      ENV["BUNDLER_TEST"] = "1"
      bundle :install
      expect(the_bundle).to include_gems "rack 1.0"
    end
  end

  describe "when just setting an ENV key as a symbol" do
    before :each do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        env :BUNDLER_TEST do
          gem "rack"
        end
      G
    end

    it "excludes the gems when the ENV variable is not set" do
      bundle :install
      expect(the_bundle).not_to include_gems "rack"
    end

    it "includes the gems when the ENV variable is set" do
      ENV["BUNDLER_TEST"] = "1"
      bundle :install
      expect(the_bundle).to include_gems "rack 1.0"
    end
  end

  describe "when setting a string to match the env" do
    before :each do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        env "BUNDLER_TEST" => "foo" do
          gem "rack"
        end
      G
    end

    it "excludes the gems when the ENV variable is not set" do
      bundle :install
      expect(the_bundle).not_to include_gems "rack"
    end

    it "excludes the gems when the ENV variable is set but does not match the condition" do
      ENV["BUNDLER_TEST"] = "1"
      bundle :install
      expect(the_bundle).not_to include_gems "rack"
    end

    it "includes the gems when the ENV variable is set and matches the condition" do
      ENV["BUNDLER_TEST"] = "foo"
      bundle :install
      expect(the_bundle).to include_gems "rack 1.0"
    end
  end

  describe "when setting a regex to match the env" do
    before :each do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        env "BUNDLER_TEST" => /foo/ do
          gem "rack"
        end
      G
    end

    it "excludes the gems when the ENV variable is not set" do
      bundle :install
      expect(the_bundle).not_to include_gems "rack"
    end

    it "excludes the gems when the ENV variable is set but does not match the condition" do
      ENV["BUNDLER_TEST"] = "fo"
      bundle :install
      expect(the_bundle).not_to include_gems "rack"
    end

    it "includes the gems when the ENV variable is set and matches the condition" do
      ENV["BUNDLER_TEST"] = "foobar"
      bundle :install
      expect(the_bundle).to include_gems "rack 1.0"
    end
  end
end
