# frozen_string_literal: true
require "spec_helper"

describe Bundler::SpecSet do
  let(:specs) do
    [
      build_spec("a", "1.0"),
      build_spec("b", "1.0"),
      build_spec("c", "1.1") do |s|
        s.dep "a", "< 2.0"
        s.dep "e", "> 0"
      end,
      build_spec("d", "2.0") do |s|
        s.dep "a", "1.0"
        s.dep "c", "~> 1.0"
      end,
      build_spec("e", "1.0.0.pre.1"),
    ].flatten
  end
  subject { described_class.new(specs) }

  context "enumerable methods" do
    it "has a length" do
      expect(subject.length).to eq(5)
    end

    it "has a size" do
      expect(subject.size).to eq(5)
    end
  end

  describe "#to_a" do
    it "returns the specs in order" do
      expect(subject.to_a.map(&:full_name)).to eq %w(
        a-1.0
        b-1.0
        e-1.0.0.pre.1
        c-1.1
        d-2.0
      )
    end
  end
end
