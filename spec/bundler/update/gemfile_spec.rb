# frozen_string_literal: true

RSpec.describe "bundle update" do
  context "with --gemfile" do
    it "finds the gemfile" do
      gemfile bundled_app("NotGemfile"), <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G

      bundle :install, gemfile: bundled_app("NotGemfile")
      bundle :update, gemfile: bundled_app("NotGemfile"), all: true

      # Specify BUNDLE_GEMFILE for `the_bundle`
      # to retrieve the proper Gemfile
      ENV["BUNDLE_GEMFILE"] = "NotGemfile"
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end
  end

  context "with gemfile set via config" do
    before do
      gemfile bundled_app("NotGemfile"), <<-G
        source "https://gem.repo1"
        gem 'myrack'
      G

      bundle "config set --local gemfile #{bundled_app("NotGemfile")}"
      bundle :install
    end

    it "uses the gemfile to update" do
      bundle "update", all: true
      bundle "list"

      expect(out).to include("myrack (1.0.0)")
    end

    it "uses the gemfile while in a subdirectory" do
      bundled_app("subdir").mkpath
      bundle "update", all: true, dir: bundled_app("subdir")
      bundle "list", dir: bundled_app("subdir")

      expect(out).to include("myrack (1.0.0)")
    end
  end
end
