# frozen_string_literal: true

RSpec.describe Bundler::SpecSet do
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

  describe "#find_by_name_and_platform" do
    let(:platform) { Gem::Platform.new("universal-darwin-64") }
    let(:platform_spec) { build_spec("b", "2.0", platform).first }
    let(:specs) do
      [
        build_spec("a", "1.0"),
        platform_spec,
      ].flatten
    end

    it "finds spec with given name and platform" do
      spec = described_class.new(specs).find_by_name_and_platform("b", platform)
      expect(spec).to eq platform_spec
    end

    it "returns nil when the name is not present" do
      spec = described_class.new(specs).find_by_name_and_platform("missing", platform)
      expect(spec).to be_nil
    end

    it "returns nil when the name exists but no spec is installable on the requested platform" do
      incompatible_platform = Gem::Platform.new("java")
      incompatible_spec = build_spec("a", "1.0", incompatible_platform).first

      spec = described_class.new([incompatible_spec]).find_by_name_and_platform("a", platform)
      expect(spec).to be_nil
    end

    it "returns the first installable spec for the given name in insertion order" do
      later_platform_spec = build_spec("b", "3.0", platform).first
      specs = [
        platform_spec,
        later_platform_spec,
      ]

      spec = described_class.new(specs).find_by_name_and_platform("b", platform)
      expect(spec).to eq platform_spec
    end
  end

  describe "#to_a" do
    it "returns the specs in order" do
      expect(subject.to_a.map(&:full_name)).to eq %w[
        a-1.0
        b-1.0
        e-1.0.0.pre.1
        c-1.1
        d-2.0
      ]
    end

    it "puts rake first when present" do
      specs = [
        build_spec("a", "1.0") {|s| s.dep "rake", ">= 0" },
        build_spec("rake", "13.0"),
      ].flatten

      expect(described_class.new(specs).to_a.map(&:full_name)).to eq %w[
        rake-13.0
        a-1.0
      ]
    end
  end

  describe "#with_overrides" do
    it "defaults to an empty override list" do
      expect(described_class.new([]).overrides).to eq([])
    end

    it "stores the overrides supplied" do
      override = Bundler::Override.new("rails", :version, ">= 8.0")
      expect(described_class.new([]).with_overrides([override]).overrides).to eq([override])
    end

    it "treats nil as an empty override list" do
      set = described_class.new([])
      override = Bundler::Override.new("rails", :version, ">= 8.0")
      set.with_overrides([override])
      set.with_overrides(nil)
      expect(set.overrides).to eq([])
    end

    it "cascades overrides to contained specs that accept them" do
      lazy = Bundler::LazySpecification.new("rails", "8.0", Gem::Platform::RUBY)
      override = Bundler::Override.new("rails", :version, ">= 8.0")
      described_class.new([lazy]).with_overrides([override])
      expect(lazy.overrides).to eq([override])
    end
  end
end
