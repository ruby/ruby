# frozen_string_literal: true

RSpec.describe "bundle issue" do
  it "exits with a message" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "rails"
    G

    bundle "issue"
    expect(out).to include "Did you find an issue with Bundler?"
    expect(out).to include "## Environment"
    expect(out).to include "## Gemfile"
    expect(out).to include "## Bundle Doctor"
  end
end
