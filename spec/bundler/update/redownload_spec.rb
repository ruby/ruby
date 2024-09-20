# frozen_string_literal: true

RSpec.describe "bundle update" do
  before :each do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G
  end

  describe "with --force" do
    it "shows a deprecation when single flag passed", bundler: 2 do
      bundle "update myrack --force"
      expect(err).to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end

    it "shows a deprecation when multiple flags passed", bundler: 2 do
      bundle "update myrack --no-color --force"
      expect(err).to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end
  end

  describe "with --redownload" do
    it "does not show a deprecation when single flag passed" do
      bundle "update myrack --redownload"
      expect(err).not_to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end

    it "does not show a deprecation when single multiple flags passed" do
      bundle "update myrack --no-color --redownload"
      expect(err).not_to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end

    it "re-installs installed gems" do
      myrack_lib = default_bundle_path("gems/myrack-1.0.0/lib/myrack.rb")
      myrack_lib.open("w") {|f| f.write("blah blah blah") }
      bundle :update, redownload: true

      expect(out).to include "Installing myrack 1.0.0"
      expect(myrack_lib.open(&:read)).to eq("MYRACK = '1.0.0'\n")
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end
  end
end
