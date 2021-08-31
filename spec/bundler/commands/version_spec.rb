# frozen_string_literal: true

require_relative "../support/path"

RSpec.describe "bundle version" do
  if Spec::Path.ruby_core?
    COMMIT_HASH = /unknown|[a-fA-F0-9]{7,}/.freeze
  else
    COMMIT_HASH = /[a-fA-F0-9]{7,}/.freeze
  end

  context "with -v" do
    it "outputs the version", :bundler => "< 3" do
      bundle "-v"
      expect(out).to eq("Bundler version #{Bundler::VERSION}")
    end

    it "outputs the version", :bundler => "3" do
      bundle "-v"
      expect(out).to eq(Bundler::VERSION)
    end
  end

  context "with --version" do
    it "outputs the version", :bundler => "< 3" do
      bundle "--version"
      expect(out).to eq("Bundler version #{Bundler::VERSION}")
    end

    it "outputs the version", :bundler => "3" do
      bundle "--version"
      expect(out).to eq(Bundler::VERSION)
    end
  end

  context "with version" do
    it "outputs the version with build metadata", :bundler => "< 3" do
      bundle "version"
      expect(out).to match(/\ABundler version #{Regexp.escape(Bundler::VERSION)} \(\d{4}-\d{2}-\d{2} commit #{COMMIT_HASH}\)\z/)
    end

    it "outputs the version with build metadata", :bundler => "3" do
      bundle "version"
      expect(out).to match(/\A#{Regexp.escape(Bundler::VERSION)} \(\d{4}-\d{2}-\d{2} commit #{COMMIT_HASH}\)\z/)
    end
  end
end
