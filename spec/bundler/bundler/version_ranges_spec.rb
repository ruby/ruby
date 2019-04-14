# frozen_string_literal: true

require "bundler/version_ranges"

RSpec.describe Bundler::VersionRanges do
  describe ".empty?" do
    shared_examples_for "empty?" do |exp, *req|
      it "returns #{exp} for #{req}" do
        r = Gem::Requirement.new(*req)
        ranges = described_class.for(r)
        expect(described_class.empty?(*ranges)).to eq(exp), "expected `#{r}` #{exp ? "" : "not "}to be empty"
      end
    end

    include_examples "empty?", false
    include_examples "empty?", false, "!= 1"
    include_examples "empty?", false, "!= 1", "= 2"
    include_examples "empty?", false, "!= 1", "> 1"
    include_examples "empty?", false, "!= 1", ">= 1"
    include_examples "empty?", false, "= 1", ">= 0.1", "<= 1.1"
    include_examples "empty?", false, "= 1", ">= 1", "<= 1"
    include_examples "empty?", false, "= 1", "~> 1"
    include_examples "empty?", false, ">= 0.z", "= 0"
    include_examples "empty?", false, ">= 0"
    include_examples "empty?", false, ">= 1.0.0", "< 2.0.0"
    include_examples "empty?", false, "~> 1"
    include_examples "empty?", false, "~> 2.0", "~> 2.1"
    include_examples "empty?", true, ">= 4.1.0", "< 5.0", "= 5.2.1"
    include_examples "empty?", true, "< 5.0", "< 5.3", "< 6.0", "< 6", "= 5.2.0", "> 2", ">= 3.0", ">= 3.1", ">= 3.2", ">= 4.0.0", ">= 4.1.0", ">= 4.2.0", ">= 4.2", ">= 4"
    include_examples "empty?", true, "!= 1", "< 2", "> 2"
    include_examples "empty?", true, "!= 1", "<= 1", ">= 1"
    include_examples "empty?", true, "< 2", "> 2"
    include_examples "empty?", true, "< 2", "> 2", "= 2"
    include_examples "empty?", true, "= 1", "!= 1"
    include_examples "empty?", true, "= 1", "= 2"
    include_examples "empty?", true, "= 1", "~> 2"
    include_examples "empty?", true, ">= 0", "<= 0.a"
    include_examples "empty?", true, "~> 2.0", "~> 3"
  end
end
