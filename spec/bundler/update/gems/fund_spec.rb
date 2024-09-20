# frozen_string_literal: true

RSpec.describe "bundle update" do
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
    end

    gemfile <<-G
      source "https://gem.repo2"
      gem 'has_funding_and_other_metadata'
      gem 'has_funding', '< 2.0'
    G

    bundle :install
  end

  context "when listed gems are updated" do
    before do
      gemfile <<-G
        source "https://gem.repo2"
        gem 'has_funding_and_other_metadata'
        gem 'has_funding'
      G

      bundle :update, all: true
    end

    it "displays fund message" do
      expect(out).to include("2 installed gems you directly depend on are looking for funding.")
    end
  end
end
