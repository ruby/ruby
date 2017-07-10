# frozen_string_literal: true
require "spec_helper"

describe "bundle inject" do
  before :each do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G
  end

  context "without a lockfile" do
    it "locks with the injected gems" do
      expect(bundled_app("Gemfile.lock")).not_to exist
      bundle "inject 'rack-obama' '> 0'"
      expect(bundled_app("Gemfile.lock").read).to match(/rack-obama/)
    end
  end

  context "with a lockfile" do
    before do
      bundle "install"
    end

    it "adds the injected gems to the Gemfile" do
      expect(bundled_app("Gemfile").read).not_to match(/rack-obama/)
      bundle "inject 'rack-obama' '> 0'"
      expect(bundled_app("Gemfile").read).to match(/rack-obama/)
    end

    it "locks with the injected gems" do
      expect(bundled_app("Gemfile.lock").read).not_to match(/rack-obama/)
      bundle "inject 'rack-obama' '> 0'"
      expect(bundled_app("Gemfile.lock").read).to match(/rack-obama/)
    end
  end

  context "with injected gems already in the Gemfile" do
    it "doesn't add existing gems" do
      bundle "inject 'rack' '> 0'"
      expect(out).to match(/cannot specify the same gem twice/i)
    end
  end

  context "when frozen" do
    before do
      bundle "install"
      bundle "config --local frozen 1"
    end

    it "injects anyway" do
      bundle "inject 'rack-obama' '> 0'"
      expect(bundled_app("Gemfile").read).to match(/rack-obama/)
    end

    it "locks with the injected gems" do
      expect(bundled_app("Gemfile.lock").read).not_to match(/rack-obama/)
      bundle "inject 'rack-obama' '> 0'"
      expect(bundled_app("Gemfile.lock").read).to match(/rack-obama/)
    end

    it "restores frozen afterwards" do
      bundle "inject 'rack-obama' '> 0'"
      config = YAML.load(bundled_app(".bundle/config").read)
      expect(config["BUNDLE_FROZEN"]).to eq("1")
    end

    it "doesn't allow Gemfile changes" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack-obama"
      G
      bundle "inject 'rack' '> 0'"
      expect(out).to match(/trying to install in deployment mode after changing/)

      expect(bundled_app("Gemfile.lock").read).not_to match(/rack-obama/)
    end
  end
end
