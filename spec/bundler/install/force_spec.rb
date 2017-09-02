# frozen_string_literal: true
require "spec_helper"

RSpec.describe "bundle install" do
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

    context "with a git gem" do
      let!(:ref) { build_git("foo", "1.0").ref_for("HEAD", 11) }

      before do
        gemfile <<-G
          gem "foo", :git => "#{lib_path("foo-1.0")}"
        G
      end

      it "re-installs installed gems" do
        foo_lib = default_bundle_path("bundler/gems/foo-1.0-#{ref}/lib/foo.rb")

        bundle! "install"
        foo_lib.open("w") {|f| f.write("blah blah blah") }
        bundle! "install --force"

        expect(out).to include "Using bundler"
        expect(out).to include "Using foo 1.0 from #{lib_path("foo-1.0")} (at master@#{ref[0, 7]})"
        expect(foo_lib.open(&:read)).to eq("FOO = '1.0'\n")
        expect(the_bundle).to include_gems "foo 1.0"
      end

      it "works on first bundle install" do
        bundle! "install --force"

        expect(out).to include "Using bundler"
        expect(out).to include "Using foo 1.0 from #{lib_path("foo-1.0")} (at master@#{ref[0, 7]})"
        expect(the_bundle).to include_gems "foo 1.0"
      end
    end
  end
end
