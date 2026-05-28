# frozen_string_literal: true

RSpec.describe "bundle install with the cooldown setting" do
  before do
    build_repo2
  end

  context "Gemfile DSL" do
    it "accepts `source ..., cooldown: N` without error" do
      install_gemfile <<-G, artifice: "compact_index"
        source "https://gem.repo2", cooldown: 5
        gem "myrack"
      G

      expect(the_bundle).to include_gems("myrack 1.0.0")
    end

    it "accepts `cooldown: 0` to disable cooldown for a source" do
      install_gemfile <<-G, artifice: "compact_index"
        source "https://gem.repo2", cooldown: 0
        gem "myrack"
      G

      expect(the_bundle).to include_gems("myrack 1.0.0")
    end
  end

  context "CLI flag" do
    before do
      gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"
      G
    end

    it "accepts --cooldown N on install" do
      bundle "install --cooldown 7", artifice: "compact_index"

      expect(the_bundle).to include_gems("myrack 1.0.0")
    end

    it "accepts --cooldown 0 as an escape hatch" do
      bundle "install --cooldown 0", artifice: "compact_index"

      expect(the_bundle).to include_gems("myrack 1.0.0")
    end
  end

  context "configuration" do
    it "reads BUNDLE_COOLDOWN as an integer" do
      gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"
      G

      bundle "install", env: { "BUNDLE_COOLDOWN" => "7" }, artifice: "compact_index"

      expect(the_bundle).to include_gems("myrack 1.0.0")
    end

    it "reads `bundle config set cooldown N`" do
      gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"
      G

      bundle "config set cooldown 7"
      bundle "install", artifice: "compact_index"

      expect(the_bundle).to include_gems("myrack 1.0.0")
    end
  end

  context "end-to-end with v2 compact index" do
    before do
      now = Time.now.utc
      build_repo3 do
        build_gem "ripe_gem", "1.0.0" do |s|
          s.date = now - (30 * 86_400)
        end
        build_gem "ripe_gem", "2.0.0" do |s|
          s.date = now - (1 * 86_400)
        end
      end
    end

    it "excludes versions within the cooldown window" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem"
      G

      bundle "install --cooldown 7", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("ripe_gem 1.0.0")
    end

    it "selects the latest version when --cooldown 0 is passed" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem"
      G

      bundle "install --cooldown 0", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("ripe_gem 2.0.0")
    end

    it "applies cooldown declared per-source in the Gemfile" do
      gemfile <<-G
        source "https://gem.repo3", cooldown: 7
        gem "ripe_gem"
      G

      bundle "install", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("ripe_gem 1.0.0")
    end

    it "is overridden by CLI --cooldown when Gemfile sets a different per-source value" do
      gemfile <<-G
        source "https://gem.repo3", cooldown: 0
        gem "ripe_gem"
      G

      bundle "install --cooldown 7", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("ripe_gem 1.0.0")
    end

    it "bypasses cooldown when bundle install uses an existing lockfile" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            ripe_gem (2.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          ripe_gem

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "install --cooldown 7", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("ripe_gem 2.0.0")
    end
  end
end
