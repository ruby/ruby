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

    it "keeps the locked version of a transitive-only target that still satisfies the override" do
      build_repo2 do
        build_gem "child", "1.0"
        build_gem "parent", "1.0" do |s|
          s.add_dependency "child", ">= 1.0"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        override "child", version: ">= 1.0"
        gem "parent"
      G

      update_repo2 do
        build_gem "child", "1.1"
      end

      bundle :install

      expect(the_bundle).to include_gems "child 1.0", "parent 1.0"
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

    it "locks the generic platform when a transitive dependency is overridden outside the parent's requirement" do
      simulate_platform "x86_64-linux" do
        install_gemfile <<-G
          source "https://gem.repo1"
          override "myrack", version: "= 1.0.0"
          gem "myrack_middleware"
        G
      end

      expect(lockfile).to include("PLATFORMS\n  ruby\n  x86_64-linux\n")
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

  context "in frozen mode" do
    it "installs a transitive-only override the lockfile already satisfies" do
      install_gemfile <<-G
        source "https://gem.repo1"
        override "myrack", version: "= 0.9.1"
        gem "myrack_middleware"
      G

      bundle :install, env: { "BUNDLE_FROZEN" => "true" }

      expect(the_bundle).to include_gems "myrack 0.9.1", "myrack_middleware 1.0"
    end

    it "installs a transitive-only override outside the parent's requirement" do
      install_gemfile <<-G
        source "https://gem.repo1"
        override "myrack", version: "= 1.0.0"
        gem "myrack_middleware"
      G

      bundle :install, env: { "BUNDLE_FROZEN" => "true" }

      expect(the_bundle).to include_gems "myrack 1.0.0", "myrack_middleware 1.0"
    end

    it "installs a metadata override on a direct dependency" do
      build_repo2 do
        build_gem "needs_old_ruby", "1.0" do |s|
          s.required_ruby_version = "< #{Gem.ruby_version}"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        override "needs_old_ruby", required_ruby_version: nil
        gem "needs_old_ruby"
      G

      bundle :install, env: { "BUNDLE_FROZEN" => "true" }

      expect(the_bundle).to include_gems "needs_old_ruby 1.0"
    end

    it "installs a metadata override on a transitive-only dependency" do
      build_repo2 do
        build_gem "needs_old_ruby", "1.0" do |s|
          s.required_ruby_version = "< #{Gem.ruby_version}"
        end
        build_gem "wraps_old", "1.0" do |s|
          s.add_dependency "needs_old_ruby"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        override "needs_old_ruby", required_ruby_version: :ignore_upper
        gem "wraps_old"
      G

      bundle :install, env: { "BUNDLE_FROZEN" => "true" }

      expect(the_bundle).to include_gems "needs_old_ruby 1.0", "wraps_old 1.0"
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

    it "preserves the locked version when a metadata override is added without bundle update" do
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
      expect(lockfile).to include("selectable (1.0)")

      bundle "update selectable"
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

    it "preserves locked versions when an :all metadata override is added without bundle update" do
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

      # :all override alone does not pre-unlock locked specs; narrow change
      # should not trigger unrelated lockfile churn.
      bundle :lock
      expect(lockfile).to include("selectable (1.0)")

      # bundle update opts the user into re-resolution under the override.
      bundle "update selectable"
      expect(lockfile).to include("selectable (2.0)")
    end
  end

  context "diagnostic on resolve failure" do
    it "lists active overrides with their Gemfile location" do
      build_repo2 do
        build_gem "needs_old_ruby", "1.0" do |s|
          s.required_ruby_version = "= #{Gem.ruby_version}.999"
        end
      end

      gemfile <<-G
        source "https://gem.repo2"
        override "needs_old_ruby", required_ruby_version: "= #{Gem.ruby_version}.999"
        gem "needs_old_ruby"
      G

      bundle :lock, raise_on_error: false
      expect(err).to include("Bundler applied the following overrides")
      expect(err).to include("override \"needs_old_ruby\", required_ruby_version:")
      expect(err).to match(/declared at Gemfile:\d+/)
    end
  end

  context "install-time compatibility" do
    it "installs a gem whose required_ruby_version excludes the current Ruby when an override removes the constraint" do
      build_repo2 do
        build_gem "needs_old_ruby", "1.0" do |s|
          s.required_ruby_version = "< #{Gem.ruby_version}"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        override "needs_old_ruby", required_ruby_version: nil
        gem "needs_old_ruby"
      G

      expect(the_bundle).to include_gems "needs_old_ruby 1.0"
    end

    it "installs a gem whose required_rubygems_version excludes the current RubyGems when an override removes it" do
      build_repo2 do
        build_gem "needs_old_rubygems", "1.0" do |s|
          s.required_rubygems_version = "< #{Gem.rubygems_version}"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        override "needs_old_rubygems", required_rubygems_version: nil
        gem "needs_old_rubygems"
      G

      expect(the_bundle).to include_gems "needs_old_rubygems 1.0"
    end

    it "installs every gem when :all required_ruby_version override is in effect" do
      build_repo2 do
        build_gem "needs_old_ruby_a", "1.0" do |s|
          s.required_ruby_version = "< #{Gem.ruby_version}"
        end
        build_gem "needs_old_ruby_b", "1.0" do |s|
          s.required_ruby_version = "< #{Gem.ruby_version}"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        override :all, required_ruby_version: :ignore_upper
        gem "needs_old_ruby_a"
        gem "needs_old_ruby_b"
      G

      expect(the_bundle).to include_gems "needs_old_ruby_a 1.0", "needs_old_ruby_b 1.0"
    end
  end

  context "with from: and to:" do
    before do
      build_repo2 do
        build_gem "b", "1.0"
        build_gem "b", "2.0"
        build_gem "c", %w[1.0 2.0] do |s|
          s.write "lib/b.rb", "B = 'c #{s.version}'"
        end
        build_gem "a", "1.0" do |s|
          s.add_dependency "b", "< 2"
        end
        build_gem "top", "1.0" do |s|
          s.add_dependency "a"
        end
        build_gem "d", "1.0" do |s|
          s.add_dependency "b"
        end
      end
    end

    it "drops a dependency of a direct dependency with to: nil" do
      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "a", to: nil
        gem "a"
      G

      expect(the_bundle).to include_gems "a 1.0"
      expect(the_bundle).not_to include_gems "b"
      expect(lockfile).to include("    a (1.0)\n      b (< 2)\n")
      expect(lockfile).not_to match(/^    b \(/)
    end

    it "drops a dependency of a transitive dependency with to: nil" do
      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "a", to: nil
        gem "top"
      G

      expect(the_bundle).to include_gems "top 1.0", "a 1.0"
      expect(the_bundle).not_to include_gems "b"
    end

    it "keeps a dropped gem that another gem still requires, without the dropped requirement" do
      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "a", to: nil
        gem "a"
        gem "d"
      G

      expect(the_bundle).to include_gems "a 1.0", "b 2.0", "d 1.0"
    end

    it "replaces a dependency of a direct dependency with to:" do
      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "a", to: "c"
        gem "a"
      G

      expect(the_bundle).to include_gems "a 1.0", "c 2.0"
      expect(lockfile).not_to match(/^    b \(/)

      run "require 'b'; puts B; puts Gem.loaded_specs.key?('b'); begin; gem 'b'; rescue Gem::LoadError => e; puts e.message; end"
      expect(out).to eq("c 2.0\nfalse\nb is not part of the bundle. Add it to your Gemfile.")
    end

    it "replaces a dependency of a transitive dependency with to:" do
      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "a", to: "c"
        gem "top"
      G

      expect(the_bundle).to include_gems "top 1.0", "a 1.0", "c 2.0"
      expect(lockfile).not_to match(/^    b \(/)
    end

    it "applies version: to the replacement" do
      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "a", to: "c", version: "< 2"
        gem "a"
      G

      expect(the_bundle).to include_gems "a 1.0", "c 1.0"
    end

    it "fails when another gem still requires the replaced gem" do
      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo2"
        override "b", from: "a", to: "c"
        gem "a"
        gem "d"
      G

      expect(err).to include(%(override "b", from: "a", to: "c" (declared at Gemfile:2) would leave both b and c in the bundle because b is still required by:\n  d\n))
      expect(err).to include(%(Replace it for each of them, for example:\n  override "b", from: "d", to: "c"))
    end

    it "allows the replaced gem and the replacement when the override rewrites nothing" do
      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "top", to: "d"
        gem "a"
        gem "d"
      G

      expect(the_bundle).to include_gems "a 1.0", "b 1.0", "d 1.0"
    end

    it "fails when the Gemfile still requires the replaced gem" do
      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo2"
        override "b", from: "a", to: "c"
        gem "a"
        gem "b"
      G

      expect(err).to include(%(override "b", from: "a", to: "c" (declared at Gemfile:2) would leave both b and c in the bundle because b is still required by:\n  the Gemfile))
    end

    it "fails when to: nil drops a gem the Gemfile requires directly" do
      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo2"
        override "b", from: "a", to: nil
        gem "a"
        gem "b"
      G

      expect(err).to include(%(override "b", from: "a", to: nil (declared at Gemfile:2) cannot drop b because the Gemfile depends on it directly))
    end

    it "warns about an override whose from: gem does not depend on the target" do
      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "aa", to: nil
        gem "a"
      G

      expect(err).to include(%(override "b", from: "aa", to: nil (declared at Gemfile:2) has no effect because the bundle has no aa that depends on b))
      expect(the_bundle).to include_gems "a 1.0", "b 1.0"
    end

    it "fetches the replacement from the source of a scoped dependency" do
      build_repo4 do
        build_gem "scoped", "1.0" do |s|
          s.add_dependency "b"
        end
        build_gem "lite", "1.0"
      end

      install_gemfile <<-G, artifice: "compact_index"
        source "https://gem.repo2"
        source "https://gem.repo4" do
          gem "scoped"
        end
        override "b", from: "scoped", to: "lite"
      G

      expect(the_bundle).to include_gems "scoped 1.0", "lite 1.0"
    end

    it "skips a dropped dependency when suggesting binstubs" do
      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "a", to: nil
        gem "a"
      G

      bundle "binstubs a"
      expect(err).to include("There are no executables for the gem a.")
    end

    it "lists the override when resolution fails" do
      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo2"
        override "b", from: "a", to: "c", version: ">= 3"
        gem "a"
      G

      expect(err).to include("Bundler applied the following overrides")
      expect(err).to match(/override "b", from: "a", to: "c", version: ">= 3" \(declared at Gemfile:\d+\)/)
    end

    it "drops the gem from an existing lockfile and brings it back when the override is removed" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "a"
      G

      expect(the_bundle).to include_gems "a 1.0", "b 1.0"

      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "a", to: nil
        gem "a"
      G

      expect(the_bundle).to include_gems "a 1.0"
      expect(the_bundle).not_to include_gems "b"
      expect(lockfile).not_to match(/^    b \(/)

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "a"
      G

      expect(the_bundle).to include_gems "a 1.0", "b 1.0"
    end

    it "replaces the gem in an existing lockfile" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "top"
      G

      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "a", to: "c"
        gem "top"
      G

      expect(the_bundle).to include_gems "top 1.0", "a 1.0", "c 2.0"
      expect(lockfile).not_to match(/^    b \(/)
    end

    it "installs and runs from the lockfile in frozen mode" do
      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "a", to: "c"
        override "b", from: "d", to: nil
        gem "a"
        gem "d"
      G

      env = { "BUNDLE_FROZEN" => "true", "BUNDLE_PATH" => bundled_app("vendor/bundle").to_s }
      bundle :install, env: env

      expect(out).to include("Installing c 2.0")
      expect(out).not_to include("Installing b ")
      bundle "exec ruby -e \"require 'b'; puts B\"", env: env
      expect(out).to eq("c 2.0")
    end

    it "refuses a frozen install when the override was added without updating the lockfile" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "a"
      G

      gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "a", to: nil
        gem "a"
      G

      bundle :install, env: { "BUNDLE_FROZEN" => "true" }, raise_on_error: false
      expect(err).to include("The dependencies in your gemfile changed, but the lockfile can't be updated because frozen mode is set")
    end

    it "refuses a frozen install when the override was removed without updating the lockfile" do
      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "a", to: nil
        gem "a"
      G

      gemfile <<-G
        source "https://gem.repo2"
        gem "a"
      G

      bundle :install, env: { "BUNDLE_FROZEN" => "true" }, raise_on_error: false
      expect(err).to include("Your lockfile includes \"a\" but not some of its dependencies")
    end

    it "keeps the override when adding a platform" do
      install_gemfile <<-G
        source "https://gem.repo2"
        override "b", from: "a", to: "c"
        gem "a"
      G

      bundle "lock --add-platform x86_64-linux"

      expect(lockfile).to include("x86_64-linux")
      expect(lockfile).not_to match(/^    b \(/)
    end

    it "locks the generic platform when a dependency is replaced" do
      simulate_platform "x86_64-linux" do
        install_gemfile <<-G
          source "https://gem.repo2"
          override "b", from: "a", to: "c"
          gem "a"
        G
      end

      expect(lockfile).to include("PLATFORMS\n  ruby\n  x86_64-linux\n")
    end
  end
end
