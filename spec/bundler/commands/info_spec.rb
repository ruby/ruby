# frozen_string_literal: true
require "spec_helper"

RSpec.describe "bundle info" do
  context "info from specific gem in gemfile" do
    before do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rails"
      G
    end

    it "prints information about the current gem" do
      bundle "info rails"
      expect(out).to include "* rails (2.3.2)
\tSummary: This is just a fake gem for testing
\tHomepage: http://example.com"
      expect(out).to match(%r{Path\: .*\/rails\-2\.3\.2})
    end

    context "given a gem that is not installed" do
      it "prints missing gem error" do
        bundle "info foo"
        expect(out).to eq "Could not find gem 'foo'."
      end
    end

    context "given a default gem shippped in ruby", :ruby_repo do
      it "prints information about the default gem", :if => (RUBY_VERSION >= "2.0") do
        bundle "info rdoc"
        expect(out).to include("* rdoc")
        expect(out).to include("Default Gem: yes")
      end
    end

    context "when gem does not have homepage" do
      before do
        build_repo1 do
          build_gem "rails", "2.3.2" do |s|
            s.executables = "rails"
            s.summary = "Just another test gem"
          end
        end
      end

      it "excludes the homepage field from the output" do
        expect(out).to_not include("Homepage:")
      end
    end

    context "given --path option" do
      it "prints the path to the gem" do
        bundle "info rails"
        expect(out).to match(%r{.*\/rails\-2\.3\.2})
      end
    end
  end
end
