# frozen_string_literal: true
require "spec_helper"
require "bundler/lockfile_parser"

RSpec.describe Bundler::LockfileParser do
  let(:lockfile_contents) { strip_whitespace(<<-L) }
    GIT
      remote: https://github.com/alloy/peiji-san.git
      revision: eca485d8dc95f12aaec1a434b49d295c7e91844b
      specs:
        peiji-san (1.2.0)

    GEM
      remote: https://rubygems.org/
      specs:
        rake (10.3.2)

    PLATFORMS
      ruby

    DEPENDENCIES
      peiji-san!
      rake

    RUBY VERSION
       ruby 2.1.3p242

    BUNDLED WITH
       1.12.0.rc.2
  L

  describe ".sections_in_lockfile" do
    it "returns the attributes" do
      attributes = described_class.sections_in_lockfile(lockfile_contents)
      expect(attributes).to contain_exactly(
        "BUNDLED WITH", "DEPENDENCIES", "GEM", "GIT", "PLATFORMS", "RUBY VERSION"
      )
    end
  end

  describe ".unknown_sections_in_lockfile" do
    let(:lockfile_contents) { strip_whitespace(<<-L) }
      UNKNOWN ATTR

      UNKNOWN ATTR 2
        random contents
    L

    it "returns the unknown attributes" do
      attributes = described_class.unknown_sections_in_lockfile(lockfile_contents)
      expect(attributes).to contain_exactly("UNKNOWN ATTR", "UNKNOWN ATTR 2")
    end
  end

  describe ".sections_to_ignore" do
    subject { described_class.sections_to_ignore(base_version) }

    context "with a nil base version" do
      let(:base_version) { nil }

      it "returns the same as > 1.0" do
        expect(subject).to contain_exactly(
          described_class::BUNDLED, described_class::RUBY, described_class::PLUGIN
        )
      end
    end

    context "with a prerelease base version" do
      let(:base_version) { Gem::Version.create("1.11.0.rc.1") }

      it "returns the same as for the release version" do
        expect(subject).to contain_exactly(
          described_class::RUBY, described_class::PLUGIN
        )
      end
    end

    context "with a current version" do
      let(:base_version) { Gem::Version.create(Bundler::VERSION) }

      it "returns an empty array" do
        expect(subject).to eq([])
      end
    end

    context "with a future version" do
      let(:base_version) { Gem::Version.create("5.5.5") }

      it "returns an empty array" do
        expect(subject).to eq([])
      end
    end
  end
end
