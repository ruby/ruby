# frozen_string_literal: true

RSpec.describe "bundle update" do
  before :each do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G
  end

  describe "with --force" do
    it "shows a deprecation when single flag passed", :bundler => 2 do
      bundle! "update rack --force"
      expect(err).to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end

    it "shows a deprecation when multiple flags passed", :bundler => 2 do
      bundle! "update rack --no-color --force"
      expect(err).to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end
  end

  describe "with --redownload" do
    it "does not show a deprecation when single flag passed" do
      bundle! "update rack --redownload"
      expect(err).not_to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end

    it "does not show a deprecation when single multiple flags passed" do
      bundle! "update rack --no-color --redownload"
      expect(err).not_to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end
  end
end
