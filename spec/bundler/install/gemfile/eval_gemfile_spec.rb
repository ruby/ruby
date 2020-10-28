# frozen_string_literal: true

RSpec.describe "bundle install with gemfile that uses eval_gemfile" do
  before do
    build_lib("gunks", :path => bundled_app.join("gems/gunks")) do |s|
      s.name    = "gunks"
      s.version = "0.0.1"
    end
  end

  context "eval-ed Gemfile points to an internal gemspec" do
    before do
      create_file "Gemfile-other", <<-G
        gemspec :path => 'gems/gunks'
      G
    end

    it "installs the gemspec specified gem" do
      install_gemfile <<-G
        eval_gemfile 'Gemfile-other'
      G
      expect(out).to include("Resolving dependencies")
      expect(out).to include("Bundle complete")

      expect(the_bundle).to include_gem "gunks 0.0.1", :source => "path@#{bundled_app("gems", "gunks")}"
    end
  end

  context "eval-ed Gemfile has relative-path gems" do
    before do
      build_lib("a", :path => bundled_app("gems/a"))
      create_file bundled_app("nested/Gemfile-nested"), <<-G
        gem "a", :path => "../gems/a"
      G

      gemfile <<-G
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
      bundle "config --local deployment true"
      bundle :install
    end
  end

  context "Gemfile uses gemspec paths after eval-ing a Gemfile" do
    before { create_file "other/Gemfile-other" }

    it "installs the gemspec specified gem" do
      install_gemfile <<-G
        eval_gemfile 'other/Gemfile-other'
        gemspec :path => 'gems/gunks'
      G
      expect(out).to include("Resolving dependencies")
      expect(out).to include("Bundle complete")

      expect(the_bundle).to include_gem "gunks 0.0.1", :source => "path@#{bundled_app("gems", "gunks")}"
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
