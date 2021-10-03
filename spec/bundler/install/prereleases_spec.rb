# frozen_string_literal: true

RSpec.describe "bundle install" do
  before do
    build_repo2 do
      build_gem "not_released", "1.0.pre"

      build_gem "has_prerelease", "1.0"
      build_gem "has_prerelease", "1.1.pre"
    end
  end

  describe "when prerelease gems are available" do
    it "finds prereleases" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "not_released"
      G
      expect(the_bundle).to include_gems "not_released 1.0.pre"
    end

    it "uses regular releases if available" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "has_prerelease"
      G
      expect(the_bundle).to include_gems "has_prerelease 1.0"
    end

    it "uses prereleases if requested" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "has_prerelease", "1.1.pre"
      G
      expect(the_bundle).to include_gems "has_prerelease 1.1.pre"
    end
  end

  describe "when prerelease gems are not available" do
    it "still works" do
      build_repo gem_repo3 do
        build_gem "rack"
      end
      FileUtils.rm_rf Dir[gem_repo3("prerelease*")]

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo3)}"
        gem "rack"
      G

      expect(the_bundle).to include_gems "rack 1.0"
    end
  end
end
