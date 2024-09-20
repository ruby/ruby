# frozen_string_literal: true

RSpec.describe "bundle fund" do
  before do
    build_repo2 do
      build_gem "has_funding_and_other_metadata" do |s|
        s.metadata = {
          "bug_tracker_uri" => "https://example.com/user/bestgemever/issues",
          "changelog_uri" => "https://example.com/user/bestgemever/CHANGELOG.md",
          "documentation_uri" => "https://www.example.info/gems/bestgemever/0.0.1",
          "homepage_uri" => "https://bestgemever.example.io",
          "mailing_list_uri" => "https://groups.example.com/bestgemever",
          "funding_uri" => "https://example.com/has_funding_and_other_metadata/funding",
          "source_code_uri" => "https://example.com/user/bestgemever",
          "wiki_uri" => "https://example.com/user/bestgemever/wiki",
        }
      end

      build_gem "has_funding", "1.2.3" do |s|
        s.metadata = {
          "funding_uri" => "https://example.com/has_funding/funding",
        }
      end

      build_gem "gem_with_dependent_funding", "1.0" do |s|
        s.add_dependency "has_funding"
      end
    end
  end

  it "prints fund information for all gems in the bundle" do
    install_gemfile <<-G
      source "https://gem.repo2"
      gem 'has_funding_and_other_metadata'
      gem 'has_funding'
      gem 'myrack-obama'
    G

    bundle "fund"

    expect(out).to include("* has_funding_and_other_metadata (1.0)\n  Funding: https://example.com/has_funding_and_other_metadata/funding")
    expect(out).to include("* has_funding (1.2.3)\n  Funding: https://example.com/has_funding/funding")
    expect(out).to_not include("myrack-obama")
  end

  it "does not consider fund information for gem dependencies" do
    install_gemfile <<-G
      source "https://gem.repo2"
      gem 'gem_with_dependent_funding'
    G

    bundle "fund"

    expect(out).to_not include("* has_funding (1.2.3)\n  Funding: https://example.com/has_funding/funding")
    expect(out).to_not include("gem_with_dependent_funding")
  end

  it "does not consider fund information for uninstalled optional dependencies" do
    install_gemfile <<-G
      source "https://gem.repo2"
      group :whatever, optional: true do
        gem 'has_funding_and_other_metadata'
      end
      gem 'has_funding'
      gem 'myrack-obama'
    G

    bundle "fund"

    expect(out).to include("* has_funding (1.2.3)\n  Funding: https://example.com/has_funding/funding")
    expect(out).to_not include("has_funding_and_other_metadata")
    expect(out).to_not include("myrack-obama")
  end

  it "considers fund information for installed optional dependencies" do
    bundle "config set with whatever"

    install_gemfile <<-G
      source "https://gem.repo2"
      group :whatever, optional: true do
        gem 'has_funding_and_other_metadata'
      end
      gem 'has_funding'
      gem 'myrack-obama'
    G

    bundle "fund"

    expect(out).to include("* has_funding_and_other_metadata (1.0)\n  Funding: https://example.com/has_funding_and_other_metadata/funding")
    expect(out).to include("* has_funding (1.2.3)\n  Funding: https://example.com/has_funding/funding")
    expect(out).to_not include("myrack-obama")
  end

  it "prints message if none of the gems have fund information" do
    install_gemfile <<-G
      source "https://gem.repo2"
      gem 'myrack-obama'
    G

    bundle "fund"

    expect(out).to include("None of the installed gems you directly depend on are looking for funding.")
  end

  describe "with --group option" do
    it "prints fund message for only specified group gems" do
      install_gemfile <<-G
      source "https://gem.repo2"
        gem 'has_funding_and_other_metadata', :group => :development
        gem 'has_funding'
      G

      bundle "fund --group development"
      expect(out).to include("* has_funding_and_other_metadata (1.0)\n  Funding: https://example.com/has_funding_and_other_metadata/funding")
      expect(out).to_not include("* has_funding (1.2.3)\n  Funding: https://example.com/has_funding/funding")
    end
  end
end
