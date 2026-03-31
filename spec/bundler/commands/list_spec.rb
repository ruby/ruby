# frozen_string_literal: true

require "json"

RSpec.describe "bundle list" do
  def find_gem_name(json:, name:)
    parse_json(json)["gems"].detect {|h| h["name"] == name }
  end

  def parse_json(json)
    JSON.parse(json)
  end

  context "in verbose mode" do
    it "logs the actual flags passed to the command" do
      install_gemfile <<-G
        source "https://gem.repo1"
      G

      bundle "list --verbose"

      expect(out).to include("Running `bundle list --verbose`")
    end
  end

  context "with name-only and paths option" do
    it "raises an error" do
      bundle "list --name-only --paths", raise_on_error: false

      expect(err).to eq "The `--name-only` and `--paths` options cannot be used together"
    end
  end

  context "with without-group and only-group option" do
    it "raises an error" do
      bundle "list --without-group dev --only-group test", raise_on_error: false

      expect(err).to eq "The `--only-group` and `--without-group` options cannot be used together"
    end
  end

  context "with invalid format option" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
      G
    end

    it "raises an error" do
      bundle "list --format=nope", raise_on_error: false

      expect(err).to eq "Unknown option`--format=nope`. Supported formats: `json`"
    end
  end

  describe "with without-group option" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"

        gem "myrack"
        gem "rspec", :group => [:test]
        gem "rails", :group => [:production]
      G
    end

    context "when group is present" do
      it "prints the gems not in the specified group" do
        bundle "list --without-group test"

        expect(out).to include("  * myrack (1.0.0)")
        expect(out).to include("  * rails (2.3.2)")
        expect(out).not_to include("  * rspec (1.2.7)")
      end

      it "prints the gems not in the specified group with json" do
        bundle "list --without-group test --format=json"

        gem = find_gem_name(json: out, name: "myrack")
        expect(gem["version"]).to eq("1.0.0")
        gem = find_gem_name(json: out, name: "rails")
        expect(gem["version"]).to eq("2.3.2")
        gem = find_gem_name(json: out, name: "rspec")
        expect(gem).to be_nil
      end
    end

    context "when group is not found" do
      it "raises an error" do
        bundle "list --without-group random", raise_on_error: false

        expect(err).to eq "`random` group could not be found."
      end
    end

    context "when multiple groups" do
      it "prints the gems not in the specified groups" do
        bundle "list --without-group test production"

        expect(out).to include("  * myrack (1.0.0)")
        expect(out).not_to include("  * rails (2.3.2)")
        expect(out).not_to include("  * rspec (1.2.7)")
      end

      it "prints the gems not in the specified groups with json" do
        bundle "list --without-group test production --format=json"

        gem = find_gem_name(json: out, name: "myrack")
        expect(gem["version"]).to eq("1.0.0")
        gem = find_gem_name(json: out, name: "rails")
        expect(gem).to be_nil
        gem = find_gem_name(json: out, name: "rspec")
        expect(gem).to be_nil
      end
    end
  end

  describe "with only-group option" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"

        gem "myrack"
        gem "rspec", :group => [:test]
        gem "rails", :group => [:production]
      G
    end

    context "when group is present" do
      it "prints the gems in the specified group" do
        bundle "list --only-group default"

        expect(out).to include("  * myrack (1.0.0)")
        expect(out).not_to include("  * rspec (1.2.7)")
      end

      it "prints the gems in the specified group with json" do
        bundle "list --only-group default --format=json"

        gem = find_gem_name(json: out, name: "myrack")
        expect(gem["version"]).to eq("1.0.0")
        gem = find_gem_name(json: out, name: "rspec")
        expect(gem).to be_nil
      end
    end

    context "when group is not found" do
      it "raises an error" do
        bundle "list --only-group random", raise_on_error: false

        expect(err).to eq "`random` group could not be found."
      end
    end

    context "when multiple groups" do
      it "prints the gems in the specified groups" do
        bundle "list --only-group default production"

        expect(out).to include("  * myrack (1.0.0)")
        expect(out).to include("  * rails (2.3.2)")
        expect(out).not_to include("  * rspec (1.2.7)")
      end

      it "prints the gems in the specified groups with json" do
        bundle "list --only-group default production --format=json"

        gem = find_gem_name(json: out, name: "myrack")
        expect(gem["version"]).to eq("1.0.0")
        gem = find_gem_name(json: out, name: "rails")
        expect(gem["version"]).to eq("2.3.2")
        gem = find_gem_name(json: out, name: "rspec")
        expect(gem).to be_nil
      end
    end
  end

  context "with name-only option" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"

        gem "myrack"
        gem "rspec", :group => [:test]
      G
    end

    it "prints only the name of the gems in the bundle" do
      bundle "list --name-only"

      expect(out).to include("myrack")
      expect(out).to include("rspec")
    end

    it "prints only the name of the gems in the bundle with json" do
      bundle "list --name-only --format=json"

      gem = find_gem_name(json: out, name: "myrack")
      expect(gem.keys).to eq(["name"])
      gem = find_gem_name(json: out, name: "rspec")
      expect(gem.keys).to eq(["name"])
    end
  end

  context "with paths option" do
    before do
      build_repo2 do
        build_gem "myrack", "1.2" do |s|
          s.executables = "myrackup"
        end

        build_gem "bar"
      end

      build_git "git_test", "1.0.0", path: lib_path("git_test")

      build_lib("gemspec_test", path: tmp("gemspec_test")) do |s|
        s.add_dependency "bar", "=1.0.0"
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"
        gem "rails"
        gem "git_test", :git => "#{lib_path("git_test")}"
        gemspec :path => "#{tmp("gemspec_test")}"
      G
    end

    it "prints the path of each gem in the bundle" do
      bundle "list --paths"
      expect(out).to match(%r{.*\/rails\-2\.3\.2})
      expect(out).to match(%r{.*\/myrack\-1\.2})
      expect(out).to match(%r{.*\/git_test\-\w})
      expect(out).to match(%r{.*\/gemspec_test})
    end

    it "prints the path of each gem in the bundle with json" do
      bundle "list --paths --format=json"

      gem = find_gem_name(json: out, name: "rails")
      expect(gem["path"]).to match(%r{.*\/rails\-2\.3\.2})
      expect(gem["git_version"]).to be_nil

      gem = find_gem_name(json: out, name: "myrack")
      expect(gem["path"]).to match(%r{.*\/myrack\-1\.2})
      expect(gem["git_version"]).to be_nil

      gem = find_gem_name(json: out, name: "git_test")
      expect(gem["path"]).to match(%r{.*\/git_test\-\w})
      expect(gem["git_version"]).to be_truthy
      expect(gem["git_version"].strip).to eq(gem["git_version"])

      gem = find_gem_name(json: out, name: "gemspec_test")
      expect(gem["path"]).to match(%r{.*\/gemspec_test})
      expect(gem["git_version"]).to be_nil
    end
  end

  context "when no gems are in the gemfile" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"
      G
    end

    it "prints message saying no gems are in the bundle" do
      bundle "list"
      expect(out).to include("No gems in the Gemfile")
    end

    it "prints empty json" do
      bundle "list --format=json"
      expect(parse_json(out)["gems"]).to eq([])
    end
  end

  context "without options" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"

        gem "myrack"
        gem "rspec", :group => [:test]
      G
    end

    it "lists gems installed in the bundle" do
      bundle "list"
      expect(out).to include("  * myrack (1.0.0)")
    end

    it "lists gems installed in the bundle with json" do
      bundle "list --format=json"

      gem = find_gem_name(json: out, name: "myrack")
      expect(gem["version"]).to eq("1.0.0")
    end
  end

  context "when using the ls alias" do
    before do
      install_gemfile <<-G
        source "https://gem.repo1"

        gem "myrack"
        gem "rspec", :group => [:test]
      G
    end

    it "runs the list command" do
      bundle "ls"
      expect(out).to include("Gems included by the bundle")
    end
  end
end
