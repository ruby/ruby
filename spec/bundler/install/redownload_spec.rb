# frozen_string_literal: true

RSpec.describe "bundle install" do
  before :each do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G
  end

  shared_examples_for "an option to force redownloading gems" do
    it "re-installs installed gems" do
      rack_lib = default_bundle_path("gems/rack-1.0.0/lib/rack.rb")

      bundle! :install
      rack_lib.open("w") {|f| f.write("blah blah blah") }
      bundle! :install, flag => true

      expect(out).to include "Installing rack 1.0.0"
      expect(rack_lib.open(&:read)).to eq("RACK = '1.0.0'\n")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "works on first bundle install" do
      bundle! :install, flag => true

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

        bundle! :install
        foo_lib.open("w") {|f| f.write("blah blah blah") }
        bundle! :install, flag => true

        expect(foo_lib.open(&:read)).to eq("FOO = '1.0'\n")
        expect(the_bundle).to include_gems "foo 1.0"
      end

      it "works on first bundle install" do
        bundle! :install, flag => true

        expect(the_bundle).to include_gems "foo 1.0"
      end
    end
  end

  describe "with --force", :bundler => 2 do
    it_behaves_like "an option to force redownloading gems" do
      let(:flag) { "force" }
    end

    it "shows a deprecation when single flag passed" do
      bundle! "install --force"
      expect(err).to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end

    it "shows a deprecation when multiple flags passed" do
      bundle! "install --no-color --force"
      expect(err).to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end
  end

  describe "with --redownload" do
    it_behaves_like "an option to force redownloading gems" do
      let(:flag) { "redownload" }
    end

    it "does not show a deprecation when single flag passed" do
      bundle! "install --redownload"
      expect(err).not_to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end

    it "does not show a deprecation when single multiple flags passed" do
      bundle! "install --no-color --redownload"
      expect(err).not_to include "[DEPRECATED] The `--force` option has been renamed to `--redownload`"
    end
  end
end
