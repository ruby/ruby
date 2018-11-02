# frozen_string_literal: true

RSpec.describe "bundle licenses" do
  before :each do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rails"
      gem "with_license"
    G
  end

  it "prints license information for all gems in the bundle" do
    bundle "licenses"

    loaded_bundler_spec = Bundler.load.specs["bundler"]
    expected = if !loaded_bundler_spec.empty?
      loaded_bundler_spec[0].license
    else
      "Unknown"
    end

    expect(out).to include("bundler: #{expected}")
    expect(out).to include("with_license: MIT")
  end

  it "performs an automatic bundle install" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rails"
      gem "with_license"
      gem "foo"
    G

    bundle "config auto_install 1"
    bundle :licenses
    expect(out).to include("Installing foo 1.0")
  end
end
