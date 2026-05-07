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
end
