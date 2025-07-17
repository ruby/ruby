# frozen_string_literal: true

RSpec.describe "fetching dependencies with a mirrored source" do
  let(:mirror) { "https://server.example.org" }

  before do
    build_repo2

    gemfile <<-G
      source "#{mirror}"
      gem 'weakling'
    G

    bundle "config set --local mirror.#{mirror} https://gem.repo2"
  end

  it "sets the 'X-Gemfile-Source' and 'User-Agent' headers and bundles successfully" do
    bundle :install, artifice: "endpoint_mirror_source"

    expect(out).to include("Installing weakling")
    expect(out).to include("Bundle complete")
    expect(the_bundle).to include_gems "weakling 0.0.3"
  end
end
