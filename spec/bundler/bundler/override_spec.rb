# frozen_string_literal: true

RSpec.describe Bundler::Override do
  describe ".find_for" do
    it "returns the matching override by target and field" do
      a = described_class.new("rails", :version, ">= 8.0")
      b = described_class.new("nokogiri", :version, :ignore_upper)
      expect(described_class.find_for([a, b], "rails", :version)).to be(a)
    end

    it "returns nil when no override matches the target" do
      a = described_class.new("rails", :version, ">= 8.0")
      expect(described_class.find_for([a], "sinatra", :version)).to be_nil
    end

    it "returns nil when no override matches the field" do
      a = described_class.new("rails", :version, ">= 8.0")
      expect(described_class.find_for([a], "rails", :required_ruby_version)).to be_nil
    end

    it "returns nil for an empty overrides list" do
      expect(described_class.find_for([], "rails", :version)).to be_nil
    end

    it "falls back to an :all override on the same field" do
      a = described_class.new(:all, :required_ruby_version, :ignore_upper)
      expect(described_class.find_for([a], "rails", :required_ruby_version)).to be(a)
    end

    it "prefers a per-gem override over a matching :all override" do
      per_gem = described_class.new("rails", :required_ruby_version, ">= 3.4")
      all_target = described_class.new(:all, :required_ruby_version, :ignore_upper)
      expect(described_class.find_for([all_target, per_gem], "rails", :required_ruby_version)).to be(per_gem)
    end

    it "does not fall back to :all when the field differs" do
      a = described_class.new(:all, :required_ruby_version, :ignore_upper)
      expect(described_class.find_for([a], "rails", :required_rubygems_version)).to be_nil
    end
  end

  describe "#apply_to" do
    context "when operation is a version spec string" do
      it "replaces the existing requirement entirely" do
        override = described_class.new("rails", :version, ">= 8.0")
        result = override.apply_to(Gem::Requirement.new(">= 1.0", "< 2.0"))
        expect(result).to eq(Gem::Requirement.new(">= 8.0"))
      end

      it "ignores the existing requirement regardless of its content" do
        override = described_class.new("rails", :version, "= 1.0")
        result = override.apply_to(Gem::Requirement.new(">= 99.0"))
        expect(result).to eq(Gem::Requirement.new("= 1.0"))
      end
    end

    context "when operation is :ignore_upper" do
      it "removes < and <= operators" do
        override = described_class.new("rails", :version, :ignore_upper)
        result = override.apply_to(Gem::Requirement.new(">= 1.0", "< 2.0"))
        expect(result).to eq(Gem::Requirement.new(">= 1.0"))
      end

      it "keeps >, >=, = operators" do
        override = described_class.new("rails", :version, :ignore_upper)
        result = override.apply_to(Gem::Requirement.new("> 1.0", "<= 2.0"))
        expect(result).to eq(Gem::Requirement.new("> 1.0"))
      end

      it "converts ~> to >= preserving the lower bound" do
        override = described_class.new("rails", :version, :ignore_upper)
        result = override.apply_to(Gem::Requirement.new("~> 1.5"))
        expect(result).to eq(Gem::Requirement.new(">= 1.5"))
      end

      it "preserves != exclusion constraints" do
        override = described_class.new("rails", :version, :ignore_upper)
        result = override.apply_to(Gem::Requirement.new(">= 1.0", "!= 1.5.0", "< 2.0"))
        expect(result).to eq(Gem::Requirement.new(">= 1.0", "!= 1.5.0"))
      end

      it "returns the default requirement when only upper bounds remain" do
        override = described_class.new("rails", :version, :ignore_upper)
        result = override.apply_to(Gem::Requirement.new("< 2.0"))
        expect(result).to eq(Gem::Requirement.default)
      end

      it "returns the default requirement when the input is nil" do
        override = described_class.new("rails", :version, :ignore_upper)
        expect(override.apply_to(nil)).to eq(Gem::Requirement.default)
      end

      it "returns the default requirement when the input is already the default" do
        override = described_class.new("rails", :version, :ignore_upper)
        expect(override.apply_to(Gem::Requirement.default)).to eq(Gem::Requirement.default)
      end
    end

    context "when operation is nil" do
      it "returns the default requirement" do
        override = described_class.new("rails", :version, nil)
        result = override.apply_to(Gem::Requirement.new(">= 1.0", "< 2.0"))
        expect(result).to eq(Gem::Requirement.default)
      end
    end

    context "when operation is unsupported" do
      it "raises ArgumentError" do
        override = described_class.new("rails", :version, 42)
        expect { override.apply_to(Gem::Requirement.default) }.to raise_error(ArgumentError, /unsupported override operation/)
      end
    end
  end
end
