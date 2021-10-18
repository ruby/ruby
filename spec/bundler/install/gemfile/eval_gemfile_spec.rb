# frozen_string_literal: true

RSpec.describe "bundle install with gemfile that uses eval_gemfile" do
  before do
    build_lib("gunks", path: bundled_app("gems/gunks")) do |s|
      s.name    = "gunks"
      s.version = "0.0.1"
    end
  end

  context "eval-ed Gemfile points to an internal gemspec" do
    before do
      create_file "Gemfile-other", <<-G
        source "#{file_uri_for(gem_repo1)}"
        gemspec :path => 'gems/gunks'
      G
    end

    it "installs the gemspec specified gem" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        eval_gemfile 'Gemfile-other'
      G
      expect(out).to include("Resolving dependencies")
      expect(out).to include("Bundle complete")

      expect(the_bundle).to include_gem "gunks 0.0.1", source: "path@#{bundled_app("gems", "gunks")}"
    end
  end

  context "eval-ed Gemfile points to an internal gemspec and uses a scoped source that duplicates the main Gemfile global source" do
    before do
      build_repo2 do
        build_gem "rails", "6.1.3.2"

        build_gem "zip-zip", "0.3"
      end

      create_file bundled_app("gems/Gemfile"), <<-G
        source "#{file_uri_for(gem_repo2)}"

        gemspec :path => "\#{__dir__}/gunks"

        source "#{file_uri_for(gem_repo2)}" do
          gem "zip-zip"
        end
      G
    end

    it "installs and finds gems correctly" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"

        gem "rails"

        eval_gemfile File.join(__dir__, "gems/Gemfile")
      G
      expect(out).to include("Resolving dependencies")
      expect(out).to include("Bundle complete")

      expect(the_bundle).to include_gem "rails 6.1.3.2"
    end
  end

  context "eval-ed Gemfile has relative-path gems" do
    before do
      build_lib("a", path: bundled_app("gems/a"))
      create_file bundled_app("nested/Gemfile-nested"), <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "a", :path => "../gems/a"
      G

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        eval_gemfile "nested/Gemfile-nested"
      G
    end

    it "installs the path gem" do
      bundle :install
      expect(the_bundle).to include_gem("a 1.0")
    end

    # Make sure that we are properly comparing path based gems between the
    # parsed lockfile and the evaluated gemfile.
    it "bundles with deployment mode configured" do
      bundle :install
      bundle "config set --local deployment true"
      bundle :install
    end
  end

  context "Gemfile uses gemspec paths after eval-ing a Gemfile" do
    before { create_file "other/Gemfile-other" }

    it "installs the gemspec specified gem" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        eval_gemfile 'other/Gemfile-other'
        gemspec :path => 'gems/gunks'
      G
      expect(out).to include("Resolving dependencies")
      expect(out).to include("Bundle complete")

      expect(the_bundle).to include_gem "gunks 0.0.1", source: "path@#{bundled_app("gems", "gunks")}"
    end
  end

  context "eval-ed Gemfile references other gemfiles" do
    it "works with relative paths" do
      create_file "other/Gemfile-other", "gem 'rack'"
      create_file "other/Gemfile", "eval_gemfile 'Gemfile-other'"
      create_file "Gemfile-alt", <<-G
        source "#{file_uri_for(gem_repo1)}"
        eval_gemfile "other/Gemfile"
      G
      install_gemfile "eval_gemfile File.expand_path('Gemfile-alt')"

      expect(the_bundle).to include_gem "rack 1.0.0"
    end
  end
end
