# frozen_string_literal: true

RSpec.describe Bundler::URINormalizer do
  describe ".normalize_suffix" do
    context "when trailing_slash is true" do
      it "adds a trailing slash when missing" do
        expect(described_class.normalize_suffix("https://example.com", trailing_slash: true)).to eq("https://example.com/")
      end

      it "keeps the trailing slash when present" do
        expect(described_class.normalize_suffix("https://example.com/", trailing_slash: true)).to eq("https://example.com/")
      end
    end

    context "when trailing_slash is false" do
      it "removes a trailing slash when present" do
        expect(described_class.normalize_suffix("https://example.com/", trailing_slash: false)).to eq("https://example.com")
      end

      it "keeps the value unchanged when no trailing slash exists" do
        expect(described_class.normalize_suffix("https://example.com", trailing_slash: false)).to eq("https://example.com")
      end
    end
  end
end
