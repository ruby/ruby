# frozen_string_literal: true

RSpec.describe "Self management", :rubygems => ">= 3.3.0.dev", :realworld => true do
  describe "auto switching" do
    let(:previous_minor) do
      "2.3.0"
    end

    before do
      build_repo2

      gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"

        gem "rack"
      G
    end

    it "installs locked version when using system path and uses it" do
      lockfile_bundled_with(previous_minor)

      bundle "config set --local path.system true"
      bundle "install", :artifice => "vcr"
      expect(out).to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{previous_minor}. Installing Bundler #{previous_minor} and restarting using that version.")

      # It uninstalls the older system bundler
      bundle "clean --force"
      expect(out).to eq("Removing bundler (#{Bundler::VERSION})")

      # App now uses locked version
      bundle "-v"
      expect(out).to end_with(previous_minor[0] == "2" ? "Bundler version #{previous_minor}" : previous_minor)

      # Subsequent installs use the locked version without reinstalling
      bundle "install --verbose"
      expect(out).to include("Using bundler #{previous_minor}")
      expect(out).not_to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{previous_minor}. Installing Bundler #{previous_minor} and restarting using that version.")
    end

    it "installs locked version when using local path and uses it" do
      lockfile_bundled_with(previous_minor)

      bundle "config set --local path vendor/bundle"
      bundle "install", :artifice => "vcr"
      expect(out).to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{previous_minor}. Installing Bundler #{previous_minor} and restarting using that version.")
      expect(vendored_gems("gems/bundler-#{previous_minor}")).to exist

      # It does not uninstall the locked bundler
      bundle "clean"
      expect(out).to be_empty

      # App now uses locked version
      bundle "-v"
      expect(out).to end_with(previous_minor[0] == "2" ? "Bundler version #{previous_minor}" : previous_minor)

      # Subsequent installs use the locked version without reinstalling
      bundle "install --verbose"
      expect(out).to include("Using bundler #{previous_minor}")
      expect(out).not_to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{previous_minor}. Installing Bundler #{previous_minor} and restarting using that version.")
    end

    it "installs locked version when using deployment option and uses it" do
      lockfile_bundled_with(previous_minor)

      bundle "config set --local deployment true"
      bundle "install", :artifice => "vcr"
      expect(out).to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{previous_minor}. Installing Bundler #{previous_minor} and restarting using that version.")
      expect(vendored_gems("gems/bundler-#{previous_minor}")).to exist

      # It does not uninstall the locked bundler
      bundle "clean"
      expect(out).to be_empty

      # App now uses locked version
      bundle "-v"
      expect(out).to end_with(previous_minor[0] == "2" ? "Bundler version #{previous_minor}" : previous_minor)

      # Subsequent installs use the locked version without reinstalling
      bundle "install --verbose"
      expect(out).to include("Using bundler #{previous_minor}")
      expect(out).not_to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{previous_minor}. Installing Bundler #{previous_minor} and restarting using that version.")
    end

    it "does not try to install a development version" do
      lockfile_bundled_with("#{previous_minor}.dev")

      bundle "install --verbose"
      expect(out).not_to match(/restarting using that version/)

      bundle "-v"
      expect(out).to eq(Bundler::VERSION[0] == "2" ? "Bundler version #{Bundler::VERSION}" : Bundler::VERSION)
    end

    it "shows a discrete message if locked bundler does not exist" do
      missing_minor ="#{Bundler::VERSION[0]}.999.999"

      lockfile_bundled_with(missing_minor)

      bundle "install", :artifice => "vcr"
      expect(err).to eq("Your lockfile is locked to a version of bundler (#{missing_minor}) that doesn't exist at https://rubygems.org/. Going on using #{Bundler::VERSION}")

      bundle "-v"
      expect(out).to eq(Bundler::VERSION[0] == "2" ? "Bundler version #{Bundler::VERSION}" : Bundler::VERSION)
    end

    private

    def lockfile_bundled_with(version)
      lockfile <<~L
        GEM
          remote: #{file_uri_for(gem_repo2)}/
          specs:
            rack (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          rack

        BUNDLED WITH
           #{version}
      L
    end
  end
end
