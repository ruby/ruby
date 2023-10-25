# frozen_string_literal: true

RSpec.describe "bundle update" do
  before :each do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack"
    G
  end

  describe "with --force" do
    it "shows a deprecation when single flag passed", :bundler => 2 do
      bundle "update rack --force"
      expect(err).to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end

    it "shows a deprecation when multiple flags passed", :bundler => 2 do
      bundle "update rack --no-color --force"
      expect(err).to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end
  end

  describe "with --redownload" do
    it "does not show a deprecation when single flag passed" do
      bundle "update rack --redownload"
      expect(err).not_to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end

    it "does not show a deprecation when single multiple flags passed" do
      bundle "update rack --no-color --redownload"
      expect(err).not_to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end

    it "re-installs installed gems" do
      rack_lib = default_bundle_path("gems/rack-1.0.0/lib/rack.rb")
      rack_lib.open("w") {|f| f.write("blah blah blah") }
      bundle :update, :redownload => true

      expect(out).to include "Installing rack 1.0.0"
      expect(rack_lib.open(&:read)).to eq("RACK = '1.0.0'\n")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end
  end
end
