# frozen_string_literal: true

RSpec.describe "override DSL" do
  context "with a version: string operation" do
    it "replaces a direct dependency requirement with the override version spec" do
      install_gemfile <<-G
        source "https://gem.repo1"
        override "myrack", version: "= 0.9.1"
        gem "myrack"
      G

      expect(the_bundle).to include_gems "myrack 0.9.1"
    end

    it "replaces a transitive dependency requirement" do
      install_gemfile <<-G
        source "https://gem.repo1"
        override "myrack", version: "= 1.0.0"
        gem "myrack_middleware"
      G

      expect(the_bundle).to include_gems "myrack 1.0.0", "myrack_middleware 1.0"
    end

    it "replaces the requirement even when the Gemfile pins a different version" do
      install_gemfile <<-G
        source "https://gem.repo1"
        override "myrack", version: "= 0.9.1"
        gem "myrack", "= 1.0.0"
      G

      expect(the_bundle).to include_gems "myrack 0.9.1"
    end

    it "applies the override against an existing lockfile" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      expect(the_bundle).to include_gems "myrack 1.0.0"

      gemfile <<-G
        source "https://gem.repo1"
        override "myrack", version: "= 0.9.1"
        gem "myrack"
      G

      bundle :install

      expect(the_bundle).to include_gems "myrack 0.9.1"
    end

    it "pins a prerelease version that the Gemfile dependency would otherwise filter out" do
      build_repo2 do
        build_gem "has_prerelease", "1.0"
        build_gem "has_prerelease", "1.1.pre"
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        override "has_prerelease", version: "= 1.1.pre"
        gem "has_prerelease"
      G

      expect(the_bundle).to include_gems "has_prerelease 1.1.pre"
    end
  end

  context "with a version: :ignore_upper operation" do
    it "strips a < upper bound on a direct dependency" do
      install_gemfile <<-G
        source "https://gem.repo1"
        override "myrack", version: :ignore_upper
        gem "myrack", "< 1.0"
      G

      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "folds ~> into >= so newer versions become reachable" do
      install_gemfile <<-G
        source "https://gem.repo1"
        override "myrack", version: :ignore_upper
        gem "myrack", "~> 0.9.1"
      G

      expect(the_bundle).to include_gems "myrack 1.0.0"
    end
  end

  context "with a version: nil operation" do
    it "drops a direct dependency's pin entirely" do
      install_gemfile <<-G
        source "https://gem.repo1"
        override "myrack", version: nil
        gem "myrack", "= 0.9.1"
      G

      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "drops a transitive dependency's pin entirely" do
      install_gemfile <<-G
        source "https://gem.repo1"
        override "myrack", version: nil
        gem "myrack_middleware"
      G

      expect(the_bundle).to include_gems "myrack 1.0.0", "myrack_middleware 1.0"
    end

    it "applies a transitive-only override against an existing lockfile" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack_middleware"
      G

      expect(the_bundle).to include_gems "myrack 0.9.1", "myrack_middleware 1.0"

      gemfile <<-G
        source "https://gem.repo1"
        override "myrack", version: "= 1.0.0"
        gem "myrack_middleware"
      G

      bundle :install

      expect(the_bundle).to include_gems "myrack 1.0.0", "myrack_middleware 1.0"
    end
  end

  context "lockfile contents" do
    it "does not record the override directive in Gemfile.lock" do
      install_gemfile <<-G
        source "https://gem.repo1"
        override "myrack", version: "= 0.9.1"
        gem "myrack"
      G

      expect(lockfile).not_to match(/override/i)
    end
  end

  context "with a required_ruby_version: operation" do
    it "lets the resolver pick a gem whose required_ruby_version excludes the current Ruby with :ignore_upper" do
      build_repo2 do
        build_gem "needs_old_ruby", "1.0" do |s|
          s.required_ruby_version = "< #{Gem.ruby_version}"
        end
      end

      gemfile <<-G
        source "https://gem.repo2"
        override "needs_old_ruby", required_ruby_version: :ignore_upper
        gem "needs_old_ruby"
      G

      bundle :lock
      expect(lockfile).to include("needs_old_ruby (1.0)")
    end

    it "lets the resolver pick the gem with required_ruby_version: nil" do
      build_repo2 do
        build_gem "needs_old_ruby", "1.0" do |s|
          s.required_ruby_version = "< #{Gem.ruby_version}"
        end
      end

      gemfile <<-G
        source "https://gem.repo2"
        override "needs_old_ruby", required_ruby_version: nil
        gem "needs_old_ruby"
      G

      bundle :lock
      expect(lockfile).to include("needs_old_ruby (1.0)")
    end

    it "applies to a transitive dependency's required_ruby_version" do
      build_repo2 do
        build_gem "needs_old_ruby", "1.0" do |s|
          s.required_ruby_version = "< #{Gem.ruby_version}"
        end
        build_gem "wraps_old", "1.0" do |s|
          s.add_dependency "needs_old_ruby"
        end
      end

      gemfile <<-G
        source "https://gem.repo2"
        override "needs_old_ruby", required_ruby_version: :ignore_upper
        gem "wraps_old"
      G

      bundle :lock
      expect(lockfile).to include("needs_old_ruby (1.0)")
      expect(lockfile).to include("wraps_old (1.0)")
    end

    it "re-resolves a direct dep when a metadata override is added against an existing lockfile" do
      build_repo2 do
        build_gem "selectable", "1.0"
        build_gem "selectable", "2.0" do |s|
          s.required_ruby_version = "< #{Gem.ruby_version}"
        end
      end

      gemfile <<-G
        source "https://gem.repo2"
        gem "selectable"
      G

      bundle :lock
      expect(lockfile).to include("selectable (1.0)")

      gemfile <<-G
        source "https://gem.repo2"
        override "selectable", required_ruby_version: :ignore_upper
        gem "selectable"
      G

      bundle :lock
      expect(lockfile).to include("selectable (2.0)")
    end
  end

  context "with a required_rubygems_version: operation" do
    it "lets the resolver pick a gem whose required_rubygems_version excludes the current RubyGems with :ignore_upper" do
      build_repo2 do
        build_gem "needs_old_rubygems", "1.0" do |s|
          s.required_rubygems_version = "< #{Gem.rubygems_version}"
        end
      end

      gemfile <<-G
        source "https://gem.repo2"
        override "needs_old_rubygems", required_rubygems_version: :ignore_upper
        gem "needs_old_rubygems"
      G

      bundle :lock
      expect(lockfile).to include("needs_old_rubygems (1.0)")
    end
  end

  context "with an :all target" do
    it "applies required_ruby_version: :ignore_upper to every gem" do
      build_repo2 do
        build_gem "needs_old_ruby_a", "1.0" do |s|
          s.required_ruby_version = "< #{Gem.ruby_version}"
        end
        build_gem "needs_old_ruby_b", "1.0" do |s|
          s.required_ruby_version = "< #{Gem.ruby_version}"
        end
      end

      gemfile <<-G
        source "https://gem.repo2"
        override :all, required_ruby_version: :ignore_upper
        gem "needs_old_ruby_a"
        gem "needs_old_ruby_b"
      G

      bundle :lock
      expect(lockfile).to include("needs_old_ruby_a (1.0)")
      expect(lockfile).to include("needs_old_ruby_b (1.0)")
    end

    it "is overridden by a per-gem override on the same field" do
      build_repo2 do
        build_gem "permissive", "1.0" do |s|
          s.required_ruby_version = "< #{Gem.ruby_version}"
        end
        build_gem "still_blocked", "1.0" do |s|
          s.required_ruby_version = "= #{Gem.ruby_version}.999"
        end
      end

      # :all says ignore_upper (would unblock both), but per-gem on
      # still_blocked nails it to a hard requirement that still fails.
      gemfile <<-G
        source "https://gem.repo2"
        override :all, required_ruby_version: :ignore_upper
        override "still_blocked", required_ruby_version: "= #{Gem.ruby_version}.999"
        gem "permissive"
        gem "still_blocked"
      G

      bundle :lock, raise_on_error: false
      expect(err).to include("still_blocked")
    end

    it "re-resolves a previously locked spec when an :all metadata override is added" do
      build_repo2 do
        build_gem "selectable", "1.0"
        build_gem "selectable", "2.0" do |s|
          s.required_ruby_version = "< #{Gem.ruby_version}"
        end
      end

      gemfile <<-G
        source "https://gem.repo2"
        gem "selectable"
      G

      bundle :lock
      expect(lockfile).to include("selectable (1.0)")

      gemfile <<-G
        source "https://gem.repo2"
        override :all, required_ruby_version: :ignore_upper
        gem "selectable"
      G

      bundle :lock
      expect(lockfile).to include("selectable (2.0)")
    end
  end
end
