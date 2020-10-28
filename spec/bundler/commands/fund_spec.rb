# frozen_string_literal: true

RSpec.describe "bundle fund" do
  it "prints fund information for all gems in the bundle" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem 'has_metadata'
      gem 'has_funding'
      gem 'rack-obama'
    G

    bundle "fund"

    expect(out).to include("* has_metadata (1.0)\n  Funding: https://example.com/has_metadata/funding")
    expect(out).to include("* has_funding (1.2.3)\n  Funding: https://example.com/has_funding/funding")
    expect(out).to_not include("rack-obama")
  end

  it "does not consider fund information for gem dependencies" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem 'gem_with_dependent_funding'
    G

    bundle "fund"

    expect(out).to_not include("* has_funding (1.2.3)\n  Funding: https://example.com/has_funding/funding")
    expect(out).to_not include("gem_with_dependent_funding")
  end

  it "prints message if none of the gems have fund information" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem 'rack-obama'
    G

    bundle "fund"

    expect(out).to include("None of the installed gems you directly depend on are looking for funding.")
  end

  describe "with --group option" do
    it "prints fund message for only specified group gems" do
      install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
        gem 'has_metadata', :group => :development
        gem 'has_funding'
      G

      bundle "fund --group development"
      expect(out).to include("* has_metadata (1.0)\n  Funding: https://example.com/has_metadata/funding")
      expect(out).to_not include("* has_funding (1.2.3)\n  Funding: https://example.com/has_funding/funding")
    end
  end
end
