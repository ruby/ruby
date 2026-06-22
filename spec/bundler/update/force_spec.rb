# frozen_string_literal: true

RSpec.describe "bundle update" do
  before :each do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G
  end

  it "re-installs installed gems with --force" do
    myrack_lib = default_bundle_path("gems/myrack-1.0.0/lib/myrack.rb")
    myrack_lib.open("w") {|f| f.write("blah blah blah") }
    bundle :update, force: true

    expect(out).to include "Installing myrack 1.0.0"
    expect(myrack_lib.open(&:read)).to eq("MYRACK = '1.0.0'\n")
    expect(the_bundle).to include_gems "myrack 1.0.0"
  end

  it "re-installs installed gems with --redownload" do
    myrack_lib = default_bundle_path("gems/myrack-1.0.0/lib/myrack.rb")
    myrack_lib.open("w") {|f| f.write("blah blah blah") }
    bundle :update, redownload: true

    expect(out).to include "Installing myrack 1.0.0"
    expect(myrack_lib.open(&:read)).to eq("MYRACK = '1.0.0'\n")
    expect(the_bundle).to include_gems "myrack 1.0.0"
  end
end
