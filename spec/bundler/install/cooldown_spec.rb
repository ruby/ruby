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

    it "rejects a negative --cooldown value" do
      bundle "install --cooldown=-7", artifice: "compact_index", raise_on_error: false

      expect(err).to match(/non-negative integer/)
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

        # parent only resolves with the in-cooldown child 2.0.0
        build_gem "child", "1.0.0" do |s|
          s.date = now - (30 * 86_400)
        end
        build_gem "child", "2.0.0" do |s|
          s.date = now - (1 * 86_400)
        end
        build_gem "parent", "1.0.0" do |s|
          s.add_dependency "child", ">= 2.0.0"
          s.date = now - (30 * 86_400)
        end

        # a cooldown-eligible version exists above the in-cooldown locked one
        build_gem "upgradable", "2.0.0" do |s|
          s.date = now - (1 * 86_400)
        end
        build_gem "upgradable", "3.0.0" do |s|
          s.date = now - (30 * 86_400)
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

    it "applies per-source Gemfile cooldown on bundle update when a lockfile exists" do
      # Converging the Gemfile sources with the lockfile sources used to drop
      # the per-source cooldown, so it only ever worked on a first resolve
      # without a lockfile.
      gemfile <<-G
        source "https://gem.repo3", cooldown: 7
        gem "ripe_gem"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            ripe_gem (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          ripe_gem

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "update ripe_gem", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("ripe_gem 1.0.0")
    end

    it "applies per-source Gemfile cooldown to gems added after the lockfile was written" do
      gemfile <<-G
        source "https://gem.repo3", cooldown: 7
        gem "ripe_gem"
        gem "child"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            ripe_gem (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          ripe_gem

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "install", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("ripe_gem 1.0.0", "child 1.0.0")
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

    it "annotates in-cooldown versions in bundle outdated table output" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem", "1.0.0"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            ripe_gem (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          ripe_gem (= 1.0.0)

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "outdated --cooldown 7", artifice: "compact_index_cooldown", raise_on_error: false

      expect(out).to match(/ripe_gem.*\(cooldown \d+d\)/)
    end

    it "annotates in-cooldown versions in bundle outdated --parseable output" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem", "1.0.0"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            ripe_gem (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          ripe_gem (= 1.0.0)

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "outdated --cooldown 7 --parseable", artifice: "compact_index_cooldown", raise_on_error: false

      expect(out).to match(/ripe_gem.*in cooldown for \d+ more day/)
    end

    it "excludes a locally-installed version that is still within the cooldown window" do
      system_gems "ripe_gem-2.0.0", gem_repo: gem_repo3

      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem"
      G

      bundle "install --cooldown 7", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("ripe_gem 1.0.0")
    end

    it "selects a locally-installed in-cooldown version when --cooldown 0 bypasses the filter" do
      system_gems "ripe_gem-2.0.0", gem_repo: gem_repo3

      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem"
      G

      bundle "install --cooldown 0", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("ripe_gem 2.0.0")
    end

    it "surfaces a cooldown hint when bundle update filters every candidate" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            ripe_gem (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          ripe_gem

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "update ripe_gem --cooldown 99999", artifice: "compact_index_cooldown", raise_on_error: false

      expect(err).to match(/excluded by the cooldown setting/)
      expect(err).to match(/--cooldown 0/)
    end

    it "keeps an in-cooldown locked version on bundle update --all instead of failing" do
      # Lockfile written before cooldown was enabled pins the now-in-cooldown
      # latest version. A full update must not downgrade below it, and cooldown
      # must not filter it out, otherwise resolution becomes impossible (#9598).
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

      bundle "update --all --cooldown 7", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("ripe_gem 2.0.0")
    end

    it "does not fail bundle outdated when the locked version is in cooldown" do
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

      bundle "outdated --cooldown 7", artifice: "compact_index_cooldown", raise_on_error: false

      # exit 0 means no outdated gems and, crucially, no resolution failure (exit 7)
      expect(exitstatus).to eq(0)
    end

    it "still applies cooldown and downgrades a gem that is updated explicitly" do
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

      bundle "update ripe_gem --cooldown 7", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("ripe_gem 1.0.0")
    end

    it "keeps an in-cooldown transitive dependency on bundle update --all" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "parent"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            child (2.0.0)
            parent (1.0.0)
              child (>= 2.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          parent

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "update --all --cooldown 7", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("parent 1.0.0", "child 2.0.0")
    end

    it "still upgrades to a cooldown-eligible version above the locked one" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "upgradable"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            upgradable (2.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          upgradable

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "update --all --cooldown 7", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("upgradable 3.0.0")
    end

    it "keeps a top-level source cooldown through a partial update with multiple sources" do
      build_repo4 do
        build_gem "solo_gem", "1.0.0" do |s|
          s.date = Time.now.utc - (30 * 86_400)
        end
        build_gem "solo_gem", "2.0.0" do |s|
          s.date = Time.now.utc - (1 * 86_400)
        end
      end

      gemfile <<-G
        source "https://gem.repo3", cooldown: 7
        gem "ripe_gem"
        source "https://gem.repo4" do
          gem "solo_gem"
        end
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            ripe_gem (1.0.0)

        GEM
          remote: https://gem.repo4/
          specs:
            solo_gem (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          ripe_gem
          solo_gem!

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "update ripe_gem", artifice: "compact_index_cooldown"

      # A partial update converges the still-locked sources, the path that used
      # to drop cooldown. repo3's cooldown must survive that even with a second
      # source in the Gemfile, so its in-window 2.0.0 stays excluded.
      expect(the_bundle).to include_gems("ripe_gem 1.0.0", "solo_gem 1.0.0")
    end

    it "carries cooldown declared on a gem-block source" do
      build_repo4 do
        build_gem "solo_gem", "1.0.0" do |s|
          s.date = Time.now.utc - (30 * 86_400)
        end
        build_gem "solo_gem", "2.0.0" do |s|
          s.date = Time.now.utc - (1 * 86_400)
        end
      end

      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem"
        source "https://gem.repo4", cooldown: 7 do
          gem "solo_gem"
        end
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            ripe_gem (1.0.0)

        GEM
          remote: https://gem.repo4/
          specs:
            solo_gem (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          ripe_gem
          solo_gem!

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "update solo_gem", artifice: "compact_index_cooldown"

      # The cooldown lives on the gem-block source, which is also converged from
      # the lockfile. A partial update of solo_gem must keep that cooldown, so
      # its in-window 2.0.0 stays excluded.
      expect(the_bundle).to include_gems("ripe_gem 1.0.0", "solo_gem 1.0.0")
    end
  end

  context "with a source that does not provide publish dates" do
    before do
      build_repo3 do
        build_gem "ripe_gem", "1.0.0"
        build_gem "ripe_gem", "2.0.0"
      end
    end

    it "cannot apply cooldown and installs the latest version" do
      # The legacy dependency API does not expose per-version publish dates, so
      # the cooldown filter has nothing to compare against and is silently
      # inactive. This pins that limitation; flip the expectation if publish
      # dates ever become available over this endpoint.
      gemfile <<-G
        source "https://gem.repo3", cooldown: 7
        gem "ripe_gem"
      G

      bundle "install", artifice: "endpoint"

      expect(the_bundle).to include_gems("ripe_gem 2.0.0")
    end
  end
end
