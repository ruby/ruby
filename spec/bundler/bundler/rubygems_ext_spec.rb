# frozen_string_literal: true

require "bundler/rubygems_ext"

RSpec.describe Gem::NameTuple do
  let(:version) { Gem::Version.new("1.0") }

  it "preserves the full name of a Ruby gem" do
    expect(described_class.new("mygem", version).full_name).to eq("mygem-1.0")
  end

  it "preserves the full name of a multi-ABI gem" do
    tuple = described_class.new("mygem", version, Gem::Platform.new("x86_64-linux"))

    expect(tuple.full_name).to eq("mygem-1.0-x86_64-linux")
  end

  it "distinguishes content-addressed artifacts that share a platform and lock name" do
    platform_tuple = described_class.new("mygem", version, "x86_64-linux")
    first = described_class.new("mygem", version, "x86_64-linux", content_address: "abcdef12")
    second = described_class.new("mygem", version, "x86_64-linux", content_address: "12345678")

    expect(first.full_name).to eq("mygem-1.0-abcdef12")
    expect(second.full_name).to eq("mygem-1.0-12345678")
    expect(first.lock_name).to eq(platform_tuple.lock_name)
    expect(second.lock_name).to eq(platform_tuple.lock_name)
  end
end

RSpec.describe Gem::SplitCompactIndexEntryOnFirstColon do
  # Reproduces the RubyGems < 4.0.13 `Gem::Resolver::APISet::GemParser` that
  # split each compact index entry on every colon, corrupting metadata values
  # that themselves contain colons.
  let(:legacy_parser_class) do
    Class.new do
      def parse_dependency(string)
        dependency = string.split(":")
        dependency[-1] = dependency[-1].split("&") if dependency.size > 1
        dependency[0] = -dependency[0]
        dependency
      end
    end
  end

  before { legacy_parser_class.prepend(described_class) }

  it "preserves colon-bearing metadata values such as created_at timestamps" do
    parser = legacy_parser_class.new

    expect(parser.send(:parse_dependency, "created_at:2026-05-12T10:00:00Z")).to eq(["created_at", ["2026-05-12T10:00:00Z"]])
  end

  it "still parses ordinary name:requirement entries" do
    parser = legacy_parser_class.new

    expect(parser.send(:parse_dependency, "myrack:>= 1.0")).to eq(["myrack", [">= 1.0"]])
  end

  it "keeps parse_dependency private" do
    parser = legacy_parser_class.new

    expect { parser.parse_dependency("created_at:x") }.to raise_error(NoMethodError, /private method/)
  end
end
