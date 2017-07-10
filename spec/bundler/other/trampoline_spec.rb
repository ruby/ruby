# frozen_string_literal: true
require "spec_helper"

describe "bundler version trampolining" do
  before do
    ENV["BUNDLE_TRAMPOLINE_DISABLE"] = nil
    ENV["BUNDLE_TRAMPOLINE_FORCE"] = "true"
    FileUtils.rm_rf(system_gem_path)
    FileUtils.cp_r(base_system_gems, system_gem_path)
  end

  context "version guessing" do
    shared_examples_for "guesses" do |version|
      it "guesses the correct bundler version" do
        bundle! "--version"
        expect(out).to eq("Bundler version #{version}")

        if bundled_app("Gemfile").file?
          bundle! "exec ruby -e 'puts Bundler::VERSION'"
          expect(out).to eq(version)
        end
      end
    end

    context "with a lockfile" do
      before do
        install_gemfile ""
        lockfile lockfile.sub(Bundler::VERSION, "1.12.0")
      end

      include_examples "guesses", "1.12.0"
    end

    context "with BUNDLER_VERSION" do
      before do
        ENV["BUNDLER_VERSION"] = "1.12.0"
      end

      context "with a lockfile" do
        before { install_gemfile "" }
        include_examples "guesses", "1.12.0"
      end

      context "without a lockfile" do
        include_examples "guesses", "1.12.0"
      end
    end

    context "with no hints" do
      include_examples "guesses", Bundler::VERSION
    end

    context "with a gemfile and no lockfile" do
      before do
        gemfile ""
      end

      include_examples "guesses", Bundler::VERSION
    end
  end

  context "without BUNDLE_TRAMPOLINE_FORCE" do
    before { ENV["BUNDLE_TRAMPOLINE_FORCE"] = nil }

    context "when the version is >= 2" do
      let(:version) { "2.7182818285" }
      before do
        simulate_bundler_version version do
          install_gemfile! ""
        end
      end

      it "trampolines automatically", :realworld => true do
        bundle "--version"
        expect(err).to include("Installing locked Bundler version #{version}...")
      end
    end
  end

  context "installing missing bundler versions", :realworld => true do
    before do
      ENV["BUNDLER_VERSION"] = "1.12.3"
      if Bundler::RubygemsIntegration.provides?("< 2.6.4")
        # necessary since we intall with 2.6.4 but the specs can run against
        # older versions that match againt the "gem" invocation
        %w(bundle bundler).each do |exe|
          system_gem_path.join("bin", exe).open("a") do |f|
            f << %(\ngem "bundler", ">= 0.a"\n)
          end
        end
      end
    end

    it "guesses & installs the correct bundler version" do
      expect(system_gem_path.join("gems", "bundler-1.12.3")).not_to exist
      bundle! "--version"
      expect(out).to eq("Bundler version 1.12.3")
      expect(system_gem_path.join("gems", "bundler-1.12.3")).to exist
    end

    it "fails gracefully when installing the bundler fails" do
      ENV["BUNDLER_VERSION"] = "9999"
      bundle "--version"
      expect(err).to start_with(<<-E.strip)
Installing locked Bundler version 9999...
Installing the inferred bundler version (= 9999) failed.
If you'd like to update to the current bundler version (#{Bundler::VERSION}) in this project, run `bundle update --bundler`.
The error was:
      E
    end

    it "displays installing message before install is started" do
      expect(system_gem_path.join("gems", "bundler-1.12.3")).not_to exist
      bundle! "--version"
      expect(err).to include("Installing locked Bundler version #{ENV["BUNDLER_VERSION"]}...")
    end

    it "doesn't display installing message if locked version is installed" do
      expect(system_gem_path.join("gems", "bundler-1.12.3")).not_to exist
      bundle! "--version"
      expect(system_gem_path.join("gems", "bundler-1.12.3")).to exist
      bundle! "--version"
      expect(err).not_to include("Installing locked Bundler version = #{ENV["BUNDLER_VERSION"]}...")
    end
  end

  context "bundle update --bundler" do
    before do
      simulate_bundler_version("1.11.1") do
        install_gemfile ""
      end
    end

    it "updates to the specified version" do
      # HACK: since no released bundler version actually supports this feature!
      bundle "update --bundler=1.12.0"
      expect(out).to include("Unknown switches '--bundler=1.12.0'")
    end

    it "updates to the specified (running) version" do
      # HACK: since no released bundler version actually supports this feature!
      bundle! "update --bundler=#{Bundler::VERSION}"
      bundle! "--version"
      expect(out).to eq("Bundler version #{Bundler::VERSION}")
    end

    it "updates to the running version" do
      # HACK: since no released bundler version actually supports this feature!
      bundle! "update --bundler"
      bundle! "--version"
      expect(out).to eq("Bundler version #{Bundler::VERSION}")
    end
  end

  context "-rbundler/setup" do
    before do
      simulate_bundler_version("1.12.0") do
        install_gemfile ""
      end
    end

    it "uses the locked version" do
      ruby! <<-R
        require "bundler/setup"
        puts Bundler::VERSION
      R
      expect(err).to be_empty
      expect(out).to include("1.12.0")
    end
  end

  context "warnings" do
    before do
      simulate_bundler_version("1.12.0") do
        install_gemfile ""
      end
    end

    it "warns user if Bundler is outdated and is < 1.13.0.rc.1" do
      ENV["BUNDLER_VERSION"] = "1.12.0"
      bundle! "install"
      expect(out).to include(<<-WARN.strip)
You're running Bundler #{Bundler::VERSION} but this project uses #{ENV["BUNDLER_VERSION"]}. To update, run `bundle update --bundler`.
      WARN
    end
  end

  context "with --verbose" do
    it "prints the running command" do
      bundle! "config", :verbose => true, :env => { "BUNDLE_POSTIT_TRAMPOLINING_VERSION" => Bundler::VERSION }
      expect(out).to start_with("Running `bundle config --verbose` with bundler #{Bundler::VERSION}")
    end
  end
end
