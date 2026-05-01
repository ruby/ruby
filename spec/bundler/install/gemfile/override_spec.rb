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
  end
end
