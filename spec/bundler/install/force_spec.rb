# frozen_string_literal: true

RSpec.describe "bundle install" do
  before :each do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G
  end

  shared_examples_for "an option to force reinstalling gems" do
    it "re-installs installed gems" do
      myrack_lib = default_bundle_path("gems/myrack-1.0.0/lib/myrack.rb")

      bundle :install
      myrack_lib.open("w") {|f| f.write("blah blah blah") }
      bundle :install, flag => true

      expect(out).to include "Installing myrack 1.0.0"
      expect(myrack_lib.open(&:read)).to eq("MYRACK = '1.0.0'\n")
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "works on first bundle install" do
      bundle :install, flag => true

      expect(out).to include "Installing myrack 1.0.0"
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "reinstalls from the cache without going back to the remote" do
      bundle :install
      bundle :install, flag => true

      expect(out).not_to include "Fetching gem metadata"
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "downloads the gem again when the cache no longer holds it" do
      bundle :install
      FileUtils.rm_rf(default_bundle_path("cache"))

      bundle :install, flag => true

      expect(out).to include "Fetching myrack 1.0.0"
      expect(default_bundle_path("cache/myrack-1.0.0.gem")).to exist
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    context "with a git gem" do
      let!(:ref) { build_git("foo", "1.0").ref_for("HEAD", 11) }

      before do
        gemfile <<-G
          source "https://gem.repo1"
          gem "foo", :git => "#{lib_path("foo-1.0")}"
        G
      end

      it "re-installs installed gems" do
        foo_lib = default_bundle_path("bundler/gems/foo-1.0-#{ref}/lib/foo.rb")

        bundle :install
        foo_lib.open("w") {|f| f.write("blah blah blah") }
        bundle :install, flag => true

        expect(foo_lib.open(&:read)).to eq("FOO = '1.0'\n")
        expect(the_bundle).to include_gems "foo 1.0"
      end

      it "works on first bundle install" do
        bundle :install, flag => true

        expect(the_bundle).to include_gems "foo 1.0"
      end
    end
  end

  describe "with --force" do
    it_behaves_like "an option to force reinstalling gems" do
      let(:flag) { "force" }
    end
  end

  describe "with --redownload" do
    it_behaves_like "an option to force reinstalling gems" do
      let(:flag) { "redownload" }
    end
  end
end
