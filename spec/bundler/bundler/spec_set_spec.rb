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

  describe "#complete_platform" do
    let(:platform) { Gem::Platform.new("x86_64-linux") }

    let(:platform_variant) do
      build_spec("needs_old_ruby", "1.0", platform).first.tap do |s|
        s.required_ruby_version = Gem::Requirement.new("< #{Gem.ruby_version}")
      end
    end

    let(:lazy_spec) do
      lazy = Bundler::LazySpecification.new("needs_old_ruby", Gem::Version.new("1.0"), Gem::Platform::RUBY)
      lazy.required_ruby_version = Gem::Requirement.new("< #{Gem.ruby_version}")
      source = double("source")
      source_specs = double("source_specs")
      allow(source).to receive(:specs).and_return(source_specs)
      allow(source_specs).to receive(:search).
        with(["needs_old_ruby", Gem::Version.new("1.0")]).and_return([platform_variant])
      lazy.source = source
      lazy
    end

    it "rejects a platform variant whose strict metadata is incompatible when no override is attached" do
      set = described_class.new([lazy_spec])
      expect(set.send(:complete_platform, platform)).to be(false)
    end

    it "accepts a platform variant when the LazySpec carries an override that allows it" do
      lazy_spec.overrides = [Bundler::Override.new("needs_old_ruby", :required_ruby_version, :ignore_upper)]
      set = described_class.new([lazy_spec])
      expect(set.send(:complete_platform, platform)).to be(true)
    end

    it "carries overrides onto a synthesized LazySpec so a follow-up complete_platform still honors them" do
      override = Bundler::Override.new("needs_old_ruby", :required_ruby_version, :ignore_upper)
      lazy_spec.overrides = [override]
      second_platform = Gem::Platform.new("aarch64-linux")
      second_variant = build_spec("needs_old_ruby", "1.0", second_platform).first.tap do |s|
        s.required_ruby_version = Gem::Requirement.new("< #{Gem.ruby_version}")
      end
      allow(lazy_spec.source.specs).to receive(:search).
        with(["needs_old_ruby", Gem::Version.new("1.0")]).and_return([platform_variant, second_variant])

      set = described_class.new([lazy_spec])
      expect(set.send(:complete_platform, platform)).to be(true)
      # The synthesized x86_64-linux variant is now in the set. If lookup
      # picks it as exemplar for the next platform check, the override list
      # must still be reachable via its overrides accessor.
      synthesized = set.to_a.find {|s| s.platform == platform }
      expect(synthesized.overrides).to eq([override])
      expect(set.send(:complete_platform, second_platform)).to be(true)
    end
  end
end
