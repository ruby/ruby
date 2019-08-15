# frozen_string_literal: true

RSpec.describe "bundle list" do
  context "with name-only and paths option" do
    it "raises an error" do
      bundle "list --name-only --paths"

      expect(err).to eq "The `--name-only` and `--paths` options cannot be used together"
    end
  end

  context "with without-group and only-group option" do
    it "raises an error" do
      bundle "list --without-group dev --only-group test"

      expect(err).to eq "The `--only-group` and `--without-group` options cannot be used together"
    end
  end

  describe "with without-group option" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        gem "rack"
        gem "rspec", :group => [:test]
      G
    end

    context "when group is present" do
      it "prints the gems not in the specified group" do
        bundle! "list --without-group test"

        expect(out).to include("  * rack (1.0.0)")
        expect(out).not_to include("  * rspec (1.2.7)")
      end
    end

    context "when group is not found" do
      it "raises an error" do
        bundle "list --without-group random"

        expect(err).to eq "`random` group could not be found."
      end
    end
  end

  describe "with only-group option" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        gem "rack"
        gem "rspec", :group => [:test]
      G
    end

    context "when group is present" do
      it "prints the gems in the specified group" do
        bundle! "list --only-group default"

        expect(out).to include("  * rack (1.0.0)")
        expect(out).not_to include("  * rspec (1.2.7)")
      end
    end

    context "when group is not found" do
      it "raises an error" do
        bundle "list --only-group random"

        expect(err).to eq "`random` group could not be found."
      end
    end
  end

  context "with name-only option" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        gem "rack"
        gem "rspec", :group => [:test]
      G
    end

    it "prints only the name of the gems in the bundle" do
      bundle "list --name-only"

      expect(out).to include("rack")
      expect(out).to include("rspec")
    end
  end

  context "with paths option" do
    before do
      build_repo2 do
        build_gem "bar"
      end

      build_git "git_test", "1.0.0", :path => lib_path("git_test")

      build_lib("gemspec_test", :path => tmp.join("gemspec_test")) do |s|
        s.add_dependency "bar", "=1.0.0"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack"
        gem "rails"
        gem "git_test", :git => "#{lib_path("git_test")}"
        gemspec :path => "#{tmp.join("gemspec_test")}"
      G
    end

    it "prints the path of each gem in the bundle" do
      bundle "list --paths"
      expect(out).to match(%r{.*\/rails\-2\.3\.2})
      expect(out).to match(%r{.*\/rack\-1\.2})
      expect(out).to match(%r{.*\/git_test\-\w})
      expect(out).to match(%r{.*\/gemspec_test})
    end
  end

  context "when no gems are in the gemfile" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
      G
    end

    it "prints message saying no gems are in the bundle" do
      bundle "list"
      expect(out).to include("No gems in the Gemfile")
    end
  end

  context "without options" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        gem "rack"
        gem "rspec", :group => [:test]
      G
    end

    it "lists gems installed in the bundle" do
      bundle "list"
      expect(out).to include("  * rack (1.0.0)")
    end
  end

  context "when using the ls alias" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        gem "rack"
        gem "rspec", :group => [:test]
      G
    end

    it "runs the list command" do
      bundle "ls"
      expect(out).to include("Gems included by the bundle")
    end
  end
end
