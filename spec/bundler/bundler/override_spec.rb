# frozen_string_literal: true

RSpec.describe Bundler::Override do
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
