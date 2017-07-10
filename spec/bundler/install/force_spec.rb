# frozen_string_literal: true
require "spec_helper"

describe "bundle install" do
  describe "with --force" do
    before :each do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G
    end

    it "re-installs installed gems" do
      rack_lib = default_bundle_path("gems/rack-1.0.0/lib/rack.rb")

      bundle "install"
      rack_lib.open("w") {|f| f.write("blah blah blah") }
      bundle "install --force"

      expect(exitstatus).to eq(0) if exitstatus
      expect(out).to include "Using bundler"
      expect(out).to include "Installing rack 1.0.0"
      expect(rack_lib.open(&:read)).to eq("RACK = '1.0.0'\n")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "works on first bundle install" do
      bundle "install --force"

      expect(exitstatus).to eq(0) if exitstatus
      expect(out).to include "Using bundler"
      expect(out).to include "Installing rack 1.0.0"
      expect(the_bundle).to include_gems "rack 1.0.0"
    end
  end
end
