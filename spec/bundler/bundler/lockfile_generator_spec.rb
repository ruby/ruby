# frozen_string_literal: true

require "bundler/lockfile_generator"

RSpec.describe Bundler::LockfileGenerator do
  describe "#add_content_addresses" do
    let(:source) { instance_double(Bundler::Source::Rubygems) }

    def lazy_spec(platform, content_address: nil)
      Bundler::LazySpecification.new("mygem", Gem::Version.new("1.0"), platform, source, content_address: content_address)
    end

    def generated_output(specs)
      definition = instance_double(Bundler::Definition, resolve: specs, locked_checksums: false)
      generator = described_class.new(definition)
      generator.send(:add_content_addresses)
      generator.out
    end

    it "writes a row the lockfile parser can read back" do
      spec = lazy_spec(Gem::Platform.new("x86_64-linux"), content_address: "abcdef12")
      output = generated_output([spec])

      expect(output).to include("CONTENT ADDRESSES\n  mygem (1.0-x86_64-linux) abcdef12\n")
      expect("  mygem (1.0-x86_64-linux) abcdef12").to match(Bundler::LockfileParser::NAME_VERSION_CONTENT_ADDRESS)
    end

    it "does not write a row for a spec with an address on the ruby platform" do
      spec = lazy_spec(Gem::Platform::RUBY, content_address: "abcdef12")

      expect(generated_output([spec])).to be_empty
      expect("  mygem (1.0) abcdef12").not_to match(Bundler::LockfileParser::NAME_VERSION_CONTENT_ADDRESS)
    end

    it "does not write a row for a spec without an address" do
      spec = lazy_spec(Gem::Platform.new("x86_64-linux"))

      expect(generated_output([spec])).to be_empty
    end
  end
end
