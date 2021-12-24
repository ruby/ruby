# frozen_string_literal: true

RSpec.describe "Self management", :rubygems => ">= 3.3.0.dev" do
  describe "auto switching" do
    let(:next_minor) do
      Bundler::VERSION.split(".").map.with_index {|s, i| i == 1 ? s.to_i + 1 : s }[0..2].join(".")
    end

    before do
      build_repo2 do
        with_built_bundler(next_minor) {|gem_path| FileUtils.mv(gem_path, gem_repo2("gems")) }
      end

      gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"

        gem "rack"
      G
    end

    it "installs locked version when using system path and uses it" do
      lockfile_bundled_with(next_minor)

      bundle "config set --local path.system true"
      bundle "install", :env => { "BUNDLER_SPEC_GEM_SOURCES" => file_uri_for(gem_repo2).to_s }
      expect(out).to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{next_minor}. Installing Bundler #{next_minor} and restarting using that version.")

      # It uninstalls the older system bundler
      bundle "clean --force"
      expect(out).to eq("Removing bundler (#{Bundler::VERSION})")

      # App now uses locked version
      bundle "-v"
      expect(out).to end_with(next_minor[0] == "2" ? "Bundler version #{next_minor}" : next_minor)

      # Subsequent installs use the locked version without reinstalling
      bundle "install --verbose"
      expect(out).to include("Using bundler #{next_minor}")
      expect(out).not_to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{next_minor}. Installing Bundler #{next_minor} and restarting using that version.")
    end

    it "installs locked version when using local path and uses it" do
      lockfile_bundled_with(next_minor)

      bundle "config set --local path vendor/bundle"
      bundle "install", :env => { "BUNDLER_SPEC_GEM_SOURCES" => file_uri_for(gem_repo2).to_s }
      expect(out).to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{next_minor}. Installing Bundler #{next_minor} and restarting using that version.")
      expect(vendored_gems("gems/bundler-#{next_minor}")).to exist

      # It does not uninstall the locked bundler
      bundle "clean"
      expect(out).to be_empty

      # App now uses locked version
      bundle "-v"
      expect(out).to end_with(next_minor[0] == "2" ? "Bundler version #{next_minor}" : next_minor)

      # Subsequent installs use the locked version without reinstalling
      bundle "install --verbose"
      expect(out).to include("Using bundler #{next_minor}")
      expect(out).not_to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{next_minor}. Installing Bundler #{next_minor} and restarting using that version.")
    end

    it "installs locked version when using deployment option and uses it" do
      lockfile_bundled_with(next_minor)

      bundle "config set --local deployment true"
      bundle "install", :env => { "BUNDLER_SPEC_GEM_SOURCES" => file_uri_for(gem_repo2).to_s }
      expect(out).to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{next_minor}. Installing Bundler #{next_minor} and restarting using that version.")
      expect(vendored_gems("gems/bundler-#{next_minor}")).to exist

      # It does not uninstall the locked bundler
      bundle "clean"
      expect(out).to be_empty

      # App now uses locked version
      bundle "-v"
      expect(out).to end_with(next_minor[0] == "2" ? "Bundler version #{next_minor}" : next_minor)

      # Subsequent installs use the locked version without reinstalling
      bundle "install --verbose"
      expect(out).to include("Using bundler #{next_minor}")
      expect(out).not_to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{next_minor}. Installing Bundler #{next_minor} and restarting using that version.")
    end

    it "does not try to install a development version" do
      lockfile_bundled_with("#{next_minor}.dev")

      bundle "install --verbose"
      expect(out).not_to match(/restarting using that version/)

      bundle "-v"
      expect(out).to eq(Bundler::VERSION[0] == "2" ? "Bundler version #{Bundler::VERSION}" : Bundler::VERSION)
    end

    it "shows a discreet message if locked bundler does not exist, and something more complete in `--verbose` mode" do
      missing_minor ="#{Bundler::VERSION[0]}.999.999"

      lockfile_bundled_with(missing_minor)

      bundle "install"
      expect(err).to eq("There was an error installing the locked bundler version (#{missing_minor}), rerun with the `--verbose` flag for more details. Going on using bundler #{Bundler::VERSION}.")

      bundle "install --verbose"
      expect(err).to include("There was an error installing the locked bundler version (#{missing_minor}), rerun with the `--verbose` flag for more details. Going on using bundler #{Bundler::VERSION}.")
      expect(err).to include("Gem::UnsatisfiableDependencyError")

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
