# frozen_string_literal: true

require_relative "../support/path"

RSpec.describe "bundle version" do
  if Spec::Path.ruby_core?
    COMMIT_HASH = /unknown|[a-fA-F0-9]{7,}/
  else
    COMMIT_HASH = /[a-fA-F0-9]{7,}/
  end

  context "with -v" do
    it "outputs the version and virtual version if set" do
      bundle "-v"
      expect(out).to eq("Bundler version #{Bundler::VERSION}")

      bundle "config simulate_version 4"
      bundle "-v"
      expect(out).to eq("#{Bundler::VERSION} (simulating Bundler 4)")
    end
  end

  context "with --version" do
    it "outputs the version and virtual version if set" do
      bundle "--version"
      expect(out).to eq("Bundler version #{Bundler::VERSION}")

      bundle "config simulate_version 4"
      bundle "--version"
      expect(out).to eq("#{Bundler::VERSION} (simulating Bundler 4)")
    end
  end

  context "with version" do
    it "outputs the version, virtual version if set, and build metadata" do
      bundle "version"
      expect(out).to match(/\ABundler version #{Regexp.escape(Bundler::VERSION)} \(\d{4}-\d{2}-\d{2} commit #{COMMIT_HASH}\)\z/)

      bundle "config simulate_version 4"
      bundle "version"
      expect(out).to match(/\A#{Regexp.escape(Bundler::VERSION)} \(simulating Bundler 4\) \(\d{4}-\d{2}-\d{2} commit #{COMMIT_HASH}\)\z/)
    end
  end
end
