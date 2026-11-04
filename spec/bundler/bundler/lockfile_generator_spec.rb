# frozen_string_literal: true

require "bundler/lockfile_generator"

RSpec.describe Bundler::LockfileGenerator do
  let(:source) { instance_double(Bundler::Source::Rubygems, checksum_store: Bundler::Checksum::Store.new) }
  let(:x86_64_linux) { Gem::Platform.new("x86_64-linux") }

  def lazy_spec(platform = x86_64_linux, content_addresses: {})
    Bundler::LazySpecification.new("mygem", Gem::Version.new("1.0"), platform, source, content_addresses: content_addresses)
  end

  def write_section(writer, specs, **definition_stubs)
    definition = instance_double(Bundler::Definition, resolve: specs, **definition_stubs)
    generator = described_class.new(definition)
    generator.send(writer)
    generator.out
  end

  describe "#add_content_addresses" do
    def content_addresses_section(specs, locked_checksums: false)
      write_section(:add_content_addresses, specs, locked_checksums: locked_checksums)
    end

    def parse_row(row)
      parser = Bundler::LockfileParser.new(<<~L)
        GEM
          remote: https://rubygems.org/
          specs:
            mygem (1.0-x86_64-linux)

        PLATFORMS
          x86_64-linux

        DEPENDENCIES
          mygem

        CONTENT ADDRESSES
        #{row}

        BUNDLED WITH
           #{Bundler::VERSION}
      L
      [parser.specs.first, parser.sources.first.checksum_store]
    end

    it "writes a row per content address, sorted by address like any lockfile section, that the parser reads back" do
      spec = lazy_spec(content_addresses: { "ffffffff" => "3.4", "00000000" => "4.0", "abcdef12" => nil })

      output = content_addresses_section([spec])

      expect(output).to eq(<<~L)

        CONTENT ADDRESSES
          mygem (1.0-x86_64-linux) 00000000 abi=4.0
          mygem (1.0-x86_64-linux) abcdef12
          mygem (1.0-x86_64-linux) ffffffff abi=3.4
      L

      parsed, = parse_row(output[/^  mygem .*abi=4\.0$/])
      expect(parsed.content_addresses).to eq("00000000" => "4.0")
    end

    it "writes each content-addressed gem's checksum under its own full name, leaving rows without one bare" do
      checksum = Bundler::Checksum.new("sha256", "aa" * 32, Bundler::Checksum::Source.new(:lock, "Gemfile.lock:1:1"))
      source.checksum_store.register(Gem::NameTuple.new("mygem", Gem::Version.new("1.0"), x86_64_linux, content_address: "abcdef12"), checksum)
      spec = lazy_spec(content_addresses: { "abcdef12" => "4.0", "01234567" => "3.4" })

      output = content_addresses_section([spec], locked_checksums: true)

      expect(output).to include("  mygem (1.0-x86_64-linux) 01234567 abi=3.4\n")
      expect(output).to include("  mygem (1.0-x86_64-linux) abcdef12 abi=4.0 sha256=#{"aa" * 32}\n")

      parsed, store = parse_row(output[/^  mygem .*sha256=.*$/])
      expect(parsed.content_addresses).to eq("abcdef12" => "4.0")
      expect(store.checksums_to_lock("mygem-1.0-abcdef12")).to eq("sha256=#{"aa" * 32}")
    end

    it "does not write checksums unless they are locked" do
      checksum = Bundler::Checksum.new("sha256", "aa" * 32, Bundler::Checksum::Source.new(:lock, "Gemfile.lock:1:1"))
      source.checksum_store.register(Gem::NameTuple.new("mygem", Gem::Version.new("1.0"), x86_64_linux, content_address: "abcdef12"), checksum)

      output = content_addresses_section([lazy_spec(content_addresses: { "abcdef12" => "4.0" })], locked_checksums: false)

      expect(output).to include("  mygem (1.0-x86_64-linux) abcdef12 abi=4.0\n")
      expect(output).not_to include("sha256")
    end

    it "does not write a row for a spec with an address on the ruby platform" do
      expect(content_addresses_section([lazy_spec(Gem::Platform::RUBY, content_addresses: { "abcdef12" => "3.4" })])).to be_empty
    end

    it "does not write a row for a spec without an address" do
      expect(content_addresses_section([lazy_spec])).to be_empty
    end
  end

  describe "#add_ruby_abis" do
    def ruby_abis_section(specs, ruby_abis)
      write_section(:add_ruby_abis, specs, ruby_abis: ruby_abis)
    end

    it "writes the Ruby ABIs in the order the definition gives them, without sorting" do
      expect(ruby_abis_section([lazy_spec(content_addresses: { "abcdef12" => "3.4" })], ["4.0", "3.3", "3.4"])).to eq("\nRUBY ABIS\n  4.0\n  3.3\n  3.4\n")
    end

    it "writes nothing when no row lists content addresses" do
      expect(ruby_abis_section([lazy_spec], ["3.4"])).to be_empty
    end

    it "writes nothing when no Ruby ABI is recorded" do
      expect(ruby_abis_section([lazy_spec(content_addresses: { "abcdef12" => "3.4" })], [])).to be_empty
    end
  end
end
