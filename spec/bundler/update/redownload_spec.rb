# frozen_string_literal: true

RSpec.describe "bundle update", :bundler => "< 2", :ruby => ">= 2.0" do
  before :each do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G
  end

  before { bundle "config major_deprecations yes" }

  describe "with --force" do
    it "shows a deprecation when single flag passed" do
      bundle! "update rack --force"
      expect(out).to include "[DEPRECATED FOR 2.0] The `--force` option has been renamed to `--redownload`"
    end

    it "shows a deprecation when multiple flags passed" do
      bundle! "update rack --no-color --force"
      expect(out).to include "[DEPRECATED FOR 2.0] The `--force` option has been renamed to `--redownload`"
    end
  end

  describe "with --redownload" do
    it "does not show a deprecation when single flag passed" do
      bundle! "update rack --redownload"
      expect(out).not_to include "[DEPRECATED FOR 2.0] The `--force` option has been renamed to `--redownload`"
    end

    it "does not show a deprecation when single multiple flags passed" do
      bundle! "update rack --no-color --redownload"
      expect(out).not_to include "[DEPRECATED FOR 2.0] The `--force` option has been renamed to `--redownload`"
    end
  end
end
