# frozen_string_literal: true

RSpec.describe "bundle update" do
  context "with --gemfile" do
    it "finds the gemfile" do
      gemfile bundled_app("NotGemfile"), <<-G
        source "file://#{gem_repo1}"
        gem 'rack'
      G

      bundle! :install, :gemfile => bundled_app("NotGemfile")
      bundle! :update, :gemfile => bundled_app("NotGemfile"), :all => bundle_update_requires_all?

      # Specify BUNDLE_GEMFILE for `the_bundle`
      # to retrieve the proper Gemfile
      ENV["BUNDLE_GEMFILE"] = "NotGemfile"
      expect(the_bundle).to include_gems "rack 1.0.0"
    end
  end

  context "with gemfile set via config" do
    before do
      gemfile bundled_app("NotGemfile"), <<-G
        source "file://#{gem_repo1}"
        gem 'rack'
      G

      bundle "config --local gemfile #{bundled_app("NotGemfile")}"
      bundle! :install
    end

    it "uses the gemfile to update" do
      bundle! "update", :all => bundle_update_requires_all?
      bundle "list"

      expect(out).to include("rack (1.0.0)")
    end

    it "uses the gemfile while in a subdirectory" do
      bundled_app("subdir").mkpath
      Dir.chdir(bundled_app("subdir")) do
        bundle! "update", :all => bundle_update_requires_all?
        bundle "list"

        expect(out).to include("rack (1.0.0)")
      end
    end
  end

  context "with prefer_gems_rb set" do
    before { bundle! "config prefer_gems_rb true" }

    it "prefers gems.rb to Gemfile" do
      create_file("gems.rb", "gem 'bundler'")
      create_file("Gemfile", "raise 'wrong Gemfile!'")

      bundle! :install
      bundle! :update, :all => bundle_update_requires_all?

      expect(bundled_app("gems.rb")).to be_file
      expect(bundled_app("Gemfile.lock")).not_to be_file

      expect(the_bundle).to include_gem "bundler #{Bundler::VERSION}"
    end
  end
end
