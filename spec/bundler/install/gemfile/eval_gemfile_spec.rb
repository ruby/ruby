# frozen_string_literal: true
require "spec_helper"

describe "bundle install with gemfile that uses eval_gemfile" do
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
      expect(out).to include("Using gunks 0.0.1 from source at `gems/gunks`")
      expect(out).to include("Bundle complete")
    end
  end

  context "eval-ed Gemfile has relative-path gems" do
    before do
      build_lib("a", :path => "gems/a")
      create_file "nested/Gemfile-nested", <<-G
        gem "a", :path => "../gems/a"
      G

      gemfile <<-G
        eval_gemfile "nested/Gemfile-nested"
      G
    end

    it "installs the path gem" do
      bundle! :install
      expect(the_bundle).to include_gem("a 1.0")
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
      expect(out).to include("Using gunks 0.0.1 from source at `gems/gunks`")
      expect(out).to include("Bundle complete")
    end
  end
end
