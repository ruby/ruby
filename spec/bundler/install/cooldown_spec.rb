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

        # an adoptable version sits between the installed one and the
        # in-cooldown newest one
        build_gem "mid_gem", "1.0.0" do |s|
          s.date = now - (30 * 86_400)
        end
        build_gem "mid_gem", "1.5.0" do |s|
          s.date = now - (30 * 86_400)
        end
        build_gem "mid_gem", "2.0.0" do |s|
          s.date = now - (1 * 86_400)
        end

        # every published version is inside the cooldown window
        build_gem "fresh_gem", "0.3.1" do |s|
          s.date = now - (1 * 86_400)
        end
        build_gem "fresh_gem", "0.3.2" do |s|
          s.date = now - (1 * 86_400)
        end

        # the generic build is outside the window, but a platform-specific
        # build of the same version was pushed inside it
        build_gem "late_platform", "1.0.0" do |s|
          s.date = now - (30 * 86_400)
        end
        build_gem "late_platform", "2.0.0" do |s|
          s.date = now - (30 * 86_400)
        end
        build_gem "late_platform", "2.0.0" do |s|
          s.platform = "x86_64-linux"
          s.date = now - (1 * 86_400)
        end
      end
    end

    it "keeps a locked all-in-cooldown gem when explicitly updating an unrelated gem" do
      # Updating ripe_gem runs an auxiliary full-update resolution to compute its
      # target version. That pass carries no prevent-downgrade floor, so without
      # exempting locked versions it re-picks fresh_gem from an empty
      # cooldown-filtered candidate set (every published 0.3.x is in the window)
      # and fails an update that never touched fresh_gem.
      gemfile <<-G
        source "https://gem.repo3", cooldown: 7
        gem "fresh_gem", "~> 0.3"
        gem "ripe_gem"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            fresh_gem (0.3.2)
            ripe_gem (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          fresh_gem (~> 0.3)
          ripe_gem

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "lock --update ripe_gem", artifice: "compact_index_cooldown"

      expect(lockfile).to include("fresh_gem (0.3.2)")
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

    it "summarizes skipped versions at the end of bundle install" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem"
      G

      bundle "install --cooldown 7", artifice: "compact_index_cooldown"

      expect(out).to include("The following gem versions were skipped by the cooldown setting:")
      expect(out).to include("* ripe_gem 2.0.0 (available in 6 days), resolved 1.0.0 instead")
      expect(the_bundle).to include_gems("ripe_gem 1.0.0")
    end

    it "summarizes skipped versions at the end of bundle update" do
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

      expect(out).to include("The following gem versions were skipped by the cooldown setting:")
      expect(out).to include("* ripe_gem 2.0.0 (available in 6 days), resolved 1.0.0 instead")
      expect(the_bundle).to include_gems("ripe_gem 1.0.0")
    end

    it "does not print a skip summary when cooldown is disabled" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem"
      G

      bundle "install --cooldown 0", artifice: "compact_index_cooldown"

      expect(out).not_to include("skipped by the cooldown setting")
    end

    it "does not print a skip summary for versions the Gemfile requirement rejects anyway" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem", "~> 1.0"
      G

      bundle "install --cooldown 7", artifice: "compact_index_cooldown"

      expect(out).not_to include("skipped by the cooldown setting")
      expect(the_bundle).to include_gems("ripe_gem 1.0.0")
    end

    it "does not print a skip summary when installing from an up-to-date lockfile" do
      gemfile <<-G
        source "https://gem.repo3", cooldown: 7
        gem "ripe_gem"
      G

      bundle "install", artifice: "compact_index_cooldown"
      expect(out).to include("skipped by the cooldown setting")

      bundle "install", artifice: "compact_index_cooldown"
      expect(out).not_to include("skipped by the cooldown setting")
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

    it "warns when the same source is declared again with a different cooldown and keeps the first value" do
      # https://github.com/rubygems/rubygems/issues/9723: a second declaration
      # of the same URL is deduped into the first one, so its cooldown cannot
      # act as a per-gem exemption.
      install_gemfile <<-G, artifice: "compact_index_cooldown"
        source "https://gem.repo3", cooldown: 7
        source "https://gem.repo3", cooldown: 0 do
          gem "ripe_gem"
        end
      G

      expect(err).to include("The source https://gem.repo3/ is declared more than once with different cooldown values (`cooldown: 0` here, `cooldown: 7` previously).")
      expect(the_bundle).to include_gems("ripe_gem 1.0.0")
    end

    it "does not warn when the same source is declared again without a cooldown" do
      install_gemfile <<-G, artifice: "compact_index_cooldown"
        source "https://gem.repo3", cooldown: 7
        source "https://gem.repo3" do
          gem "ripe_gem"
        end
      G

      expect(err).not_to include("cooldown")
      expect(the_bundle).to include_gems("ripe_gem 1.0.0")
    end

    it "does not warn when the same source is declared again with the same cooldown" do
      install_gemfile <<-G, artifice: "compact_index_cooldown"
        source "https://gem.repo3", cooldown: 7
        source "https://gem.repo3", cooldown: 7 do
          gem "ripe_gem"
        end
      G

      expect(err).not_to include("cooldown")
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

    it "shows the newest out-of-cooldown version next to the in-cooldown newest one" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "mid_gem", "1.0.0"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            mid_gem (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          mid_gem (= 1.0.0)

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "outdated --cooldown 7 --parseable", artifice: "compact_index_cooldown", raise_on_error: false

      expect(out).to match(/mid_gem \(newest 2\.0\.0, installed 1\.0\.0.*in cooldown for \d+ more days, newest out of cooldown 1\.5\.0\)/)

      bundle "outdated --cooldown 7", artifice: "compact_index_cooldown", raise_on_error: false

      expect(out).to match(/mid_gem.*2\.0\.0 \(cooldown \d+d, 1\.5\.0 out of cooldown\)/)
    end

    it "shows the resolved version without cooldown notes in strict mode" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "mid_gem"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            mid_gem (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          mid_gem

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "outdated --strict --cooldown 7 --parseable", artifice: "compact_index_cooldown", raise_on_error: false

      # in strict mode "newest" is the resolved (cooldown-filtered) version
      # itself, so the annotations have nothing to add
      expect(out).to match(/mid_gem \(newest 1\.5\.0, installed 1\.0\.0/)
      expect(out).not_to include("cooldown")
    end

    it "shows no out-of-cooldown note when every version is inside the window" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "fresh_gem", "0.3.1"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            fresh_gem (0.3.1)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          fresh_gem (= 0.3.1)

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "outdated --cooldown 7 --parseable", artifice: "compact_index_cooldown", raise_on_error: false

      expect(out).to match(/fresh_gem.*in cooldown for \d+ more day/)
      expect(out).not_to include("out of cooldown")
    end

    it "leaves bundle outdated output untouched when cooldown is not enabled" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "mid_gem", "1.0.0"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo3/
          specs:
            mid_gem (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          mid_gem (= 1.0.0)

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "outdated --parseable", artifice: "compact_index_cooldown", raise_on_error: false

      expect(out).to match(/mid_gem \(newest 2\.0\.0, installed 1\.0\.0/)
      expect(out).not_to include("cooldown")
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
      now = Time.now.utc
      build_repo4 do
        build_gem "solo_gem", "1.0.0" do |s|
          s.date = now - (30 * 86_400)
        end
        build_gem "solo_gem", "2.0.0" do |s|
          s.date = now - (1 * 86_400)
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
      now = Time.now.utc
      build_repo4 do
        build_gem "solo_gem", "1.0.0" do |s|
          s.date = now - (30 * 86_400)
        end
        build_gem "solo_gem", "2.0.0" do |s|
          s.date = now - (1 * 86_400)
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

    it "applies per-source Gemfile cooldown to a gem added via bundle add" do
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

      bundle "add child", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("child 1.0.0")
    end

    it "applies per-source Gemfile cooldown on bundle lock --update" do
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

      bundle "lock --update ripe_gem", artifice: "compact_index_cooldown"

      expect(lockfile).to include("ripe_gem (1.0.0)")
      expect(lockfile).not_to include("ripe_gem (2.0.0)")
    end

    it "still applies cooldown and downgrades a gem explicitly updated via bundle lock --update" do
      gemfile <<-G
        source "https://gem.repo3", cooldown: 7
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

      bundle "lock --update ripe_gem", artifice: "compact_index_cooldown"

      expect(lockfile).to include("ripe_gem (1.0.0)")
      expect(lockfile).not_to include("ripe_gem (2.0.0)")
    end

    it "excludes a version on every platform when a platform-specific build of it is inside the window" do
      # Exclusion is keyed on [name, version] and deliberately ignores
      # platform: otherwise pushing a fresh platform-specific build under an
      # already-ripe version number would slip new code past the cooldown.
      gemfile <<-G
        source "https://gem.repo3"
        gem "late_platform"
      G

      bundle "install --cooldown 7", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("late_platform 1.0.0")
    end

    it "selects the version with a late platform-specific build when --cooldown 0 bypasses the filter" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "late_platform"
      G

      bundle "install --cooldown 0", artifice: "compact_index_cooldown"

      # On x86_64-linux hosts this resolves to the platform-specific build, so
      # assert on the lockfile instead of the installed platform.
      expect(lockfile).to include("late_platform (2.0.0")
      expect(lockfile).not_to include("late_platform (1.0.0)")
    end

    it "applies CLI --cooldown on bundle lock --update" do
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

      bundle "lock --update --cooldown 7", artifice: "compact_index_cooldown"

      expect(lockfile).to include("ripe_gem (1.0.0)")
      expect(lockfile).not_to include("ripe_gem (2.0.0)")
    end

    it "rejects a negative --cooldown value on bundle lock" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem"
      G

      bundle "lock --cooldown=-7", artifice: "compact_index_cooldown", raise_on_error: false

      expect(err).to match(/non-negative integer/)
    end

    it "applies CLI --cooldown on bundle cache" do
      gemfile <<-G
        source "https://gem.repo3"
        gem "ripe_gem"
      G

      bundle "cache --cooldown 7", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("ripe_gem 1.0.0")
      expect(bundled_app("vendor/cache/ripe_gem-1.0.0.gem")).to exist
    end

    it "ignores cooldown and installs the locked version when frozen" do
      # Frozen installs read the lockfile instead of resolving, so cooldown has
      # no say. A version already locked inside the window must still install.
      gemfile <<-G
        source "https://gem.repo3", cooldown: 7
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

      bundle "config set frozen true"
      bundle "install", artifice: "compact_index_cooldown"

      expect(the_bundle).to include_gems("ripe_gem 2.0.0")
    end

    it "keys per-source cooldown by the declared URI even behind a mirror" do
      # A mirror rewrites the fetch URI, but cooldown is recorded under the URI
      # written in the Gemfile. The cooldown must still apply through the
      # redirect to the mirror that actually serves the gems.
      bundle "config set mirror.https://gem.repo2 https://gem.repo3"

      gemfile <<-G
        source "https://gem.repo2", cooldown: 7
        gem "ripe_gem"
      G

      bundle "install", artifice: "compact_index_cooldown",
                        env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo3.to_s }

      expect(the_bundle).to include_gems("ripe_gem 1.0.0")
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
