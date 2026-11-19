# frozen_string_literal: true

require "bundler/rubygems_ext"

RSpec.describe Gem::NameTupleContentAddress do
  # Reproduces the RubyGems < 4.1 `Gem::NameTuple`, which neither takes a
  # content address nor includes one in its full name.
  let(:legacy_name_tuple_class) do
    Class.new(Gem::NameTuple) do
      def initialize(name, version, platform = Gem::Platform::RUBY)
        @name = name
        @version = version

        platform &&= platform.to_s
        platform = Gem::Platform::RUBY if !platform || platform.empty?
        @platform = platform
      end

      def full_name
        case @platform
        when nil, "", Gem::Platform::RUBY
          "#{@name}-#{@version}"
        else
          "#{@name}-#{@version}-#{@platform}"
        end
      end
    end
  end

  let(:version) { Gem::Version.new("1.0") }

  before { legacy_name_tuple_class.prepend(described_class) }

  it "preserves the full name of a Ruby gem" do
    expect(legacy_name_tuple_class.new("mygem", version).full_name).to eq("mygem-1.0")
  end

  it "preserves the full name of a multi-ABI gem" do
    tuple = legacy_name_tuple_class.new("mygem", version, Gem::Platform.new("x86_64-linux"))

    expect(tuple.full_name).to eq("mygem-1.0-x86_64-linux")
  end

  it "distinguishes content-addressed artifacts that share a platform and lock name" do
    platform_tuple = legacy_name_tuple_class.new("mygem", version, "x86_64-linux")
    first = legacy_name_tuple_class.new("mygem", version, "x86_64-linux", content_address: "abcdef12")
    second = legacy_name_tuple_class.new("mygem", version, "x86_64-linux", content_address: "12345678")

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
