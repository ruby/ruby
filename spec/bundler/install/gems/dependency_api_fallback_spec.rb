# frozen_string_literal: true

RSpec.describe "gemcutter's dependency API" do
  context "when Gemcutter API takes too long to respond" do
    before do
      bundle "config set timeout 1"
    end

    it "times out and falls back on the modern index" do
      install_gemfile <<-G, artifice: "endpoint_timeout"
        source "https://gem.repo1"
        gem "myrack"
      G

      expect(out).to include("Fetching source index from https://gem.repo1/")
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end
  end
end
