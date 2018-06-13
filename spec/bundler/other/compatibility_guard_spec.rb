# frozen_string_literal: true

RSpec.describe "bundler compatibility guard" do
  context "when the bundler version is 2+" do
    before { simulate_bundler_version "2.0.a" }

    context "when running on Ruby < 2.3", :ruby => "< 2.3" do
      before { simulate_rubygems_version "2.6.11" }

      it "raises a friendly error" do
        bundle :version
        expect(err).to eq("Bundler 2 requires Ruby 2.3 or later. Either install bundler 1 or update to a supported Ruby version.")
      end
    end

    context "when running on RubyGems < 2.5", :ruby => ">= 2.5" do
      before { simulate_rubygems_version "1.3.6" }

      it "raises a friendly error" do
        bundle :version
        expect(err).to eq("Bundler 2 requires RubyGems 2.5 or later. Either install bundler 1 or update to a supported RubyGems version.")
      end
    end
  end
end
