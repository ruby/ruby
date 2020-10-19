# frozen_string_literal: true

RSpec.describe "bundle update" do
  before do
    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem 'has_metadata'
      gem 'has_funding', '< 2.0'
    G

    bundle :install
  end

  context "when listed gems are updated" do
    before do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'has_metadata'
        gem 'has_funding'
      G

      bundle :update, :all => true
    end

    it "displays fund message" do
      expect(out).to include("2 installed gems you directly depend on are looking for funding.")
    end
  end
end
