# frozen_string_literal: true

require "bundler/lockfile_parser"

RSpec.describe Bundler::LockfileParser do
  let(:lockfile_contents) { <<~L }
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

    CHECKSUMS
      rake (10.3.2) sha256=814828c34f1315d7e7b7e8295184577cc4e969bad6156ac069d02d63f58d82e8

    RUBY VERSION
       ruby 2.1.3p242

    BUNDLED WITH
       1.12.0.rc.2
  L

  describe ".sections_in_lockfile" do
    it "returns the attributes" do
      attributes = described_class.sections_in_lockfile(lockfile_contents)
      expect(attributes).to contain_exactly(
        "BUNDLED WITH", "CHECKSUMS", "DEPENDENCIES", "GEM", "GIT", "PLATFORMS", "RUBY VERSION"
      )
    end
  end

  describe ".unknown_sections_in_lockfile" do
    let(:lockfile_contents) { <<~L }
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
          described_class::BUNDLED, described_class::CHECKSUMS, described_class::RUBY, described_class::PLUGIN
        )
      end
    end

    context "with a prerelease base version" do
      let(:base_version) { Gem::Version.create("1.11.0.rc.1") }

      it "returns the same as for the release version" do
        expect(subject).to contain_exactly(
          described_class::CHECKSUMS, described_class::RUBY, described_class::PLUGIN
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

  describe "#initialize" do
    before { allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app("gems.rb")) }
    subject { described_class.new(lockfile_contents) }

    let(:sources) do
      [Bundler::Source::Git.new("uri" => "https://github.com/alloy/peiji-san.git", "revision" => "eca485d8dc95f12aaec1a434b49d295c7e91844b"),
       Bundler::Source::Rubygems.new("remotes" => ["https://rubygems.org"])]
    end
    let(:dependencies) do
      {
        "peiji-san" => Bundler::Dependency.new("peiji-san", ">= 0"),
        "rake" => Bundler::Dependency.new("rake", ">= 0"),
      }
    end
    let(:specs) do
      [
        Bundler::LazySpecification.new("peiji-san", v("1.2.0"), Gem::Platform::RUBY),
        Bundler::LazySpecification.new("rake", v("10.3.2"), Gem::Platform::RUBY),
      ]
    end
    let(:platforms) { [Gem::Platform::RUBY] }
    let(:bundler_version) { Gem::Version.new("1.12.0.rc.2") }
    let(:ruby_version) { "ruby 2.1.3p242" }
    let(:lockfile_path) { Bundler.default_lockfile.relative_path_from(Dir.pwd) }
    let(:rake_sha256_checksum) do
      Bundler::Checksum.from_lock(
        "sha256=814828c34f1315d7e7b7e8295184577cc4e969bad6156ac069d02d63f58d82e8",
        "#{lockfile_path}:20:17"
      )
    end
    let(:rake_checksums) { [rake_sha256_checksum] }

    shared_examples_for "parsing" do
      it "parses correctly" do
        expect(subject.sources).to eq sources
        expect(subject.dependencies).to eq dependencies
        expect(subject.specs).to eq specs
        expect(Hash[subject.specs.map {|s| [s, s.dependencies] }]).to eq Hash[subject.specs.map {|s| [s, s.dependencies] }]
        expect(subject.platforms).to eq platforms
        expect(subject.bundler_version).to eq bundler_version
        expect(subject.ruby_version).to eq ruby_version
        rake_spec = specs.last
        checksums = subject.sources.last.checksum_store.to_lock(specs.last)
        expect(checksums).to eq("#{rake_spec.lock_name} #{rake_checksums.map(&:to_lock).sort.join(",")}")
      end
    end

    include_examples "parsing"

    context "when an extra section is at the end" do
      let(:lockfile_contents) { super() + "\n\nFOO BAR\n  baz\n   baa\n    qux\n" }
      include_examples "parsing"
    end

    context "when an extra section is at the start" do
      let(:lockfile_contents) { "FOO BAR\n  baz\n   baa\n    qux\n\n" + super() }
      include_examples "parsing"
    end

    context "when an extra section is in the middle" do
      let(:lockfile_contents) { super().split(/(?=GEM)/).insert(1, "FOO BAR\n  baz\n   baa\n    qux\n\n").join }
      include_examples "parsing"
    end

    context "when a dependency has options" do
      let(:lockfile_contents) { super().sub("peiji-san!", "peiji-san!\n    foo: bar") }
      include_examples "parsing"
    end

    context "when the checksum is urlsafe base64 encoded" do
      let(:lockfile_contents) do
        super().sub(
          "sha256=814828c34f1315d7e7b7e8295184577cc4e969bad6156ac069d02d63f58d82e8",
          "sha256=gUgow08TFdfnt-gpUYRXfMTpabrWFWrAadAtY_WNgug="
        )
      end
      include_examples "parsing"
    end

    context "when the checksum is of an unknown algorithm" do
      let(:rake_sha512_checksum) do
        Bundler::Checksum.from_lock(
          "sha512=pVDn9GLmcFkz8vj1ueiVxj5uGKkAyaqYjEX8zG6L5O4BeVg3wANaKbQdpj/B82Nd/MHVszy6polHcyotUdwilQ==",
          "#{lockfile_path}:20:17"
        )
      end
      let(:lockfile_contents) do
        super().sub(
          "sha256=",
          "sha512=pVDn9GLmcFkz8vj1ueiVxj5uGKkAyaqYjEX8zG6L5O4BeVg3wANaKbQdpj/B82Nd/MHVszy6polHcyotUdwilQ==,sha256="
        )
      end
      let(:rake_checksums) { [rake_sha256_checksum, rake_sha512_checksum] }
      include_examples "parsing"
    end

    context "when CHECKSUMS has duplicate checksums in the lockfile that don't match" do
      let(:bad_checksum) { "sha256=c0ffee11c0ffee11c0ffee11c0ffee11c0ffee11c0ffee11c0ffee11c0ffee11" }
      let(:lockfile_contents) { super().split(/(?<=CHECKSUMS\n)/m).insert(1, "  rake (10.3.2) #{bad_checksum}\n").join }

      it "raises a security error" do
        expect { subject }.to raise_error(Bundler::SecurityError) do |e|
          expect(e.message).to match <<~MESSAGE
            Bundler found mismatched checksums. This is a potential security risk.
              rake (10.3.2) #{bad_checksum}
                from the lockfile CHECKSUMS at #{lockfile_path}:20:17
              rake (10.3.2) #{rake_sha256_checksum.to_lock}
                from the lockfile CHECKSUMS at #{lockfile_path}:21:17

            To resolve this issue you can either:
              1. remove the matching checksum in #{lockfile_path}:21:17
              2. run `bundle install`
            or if you are sure that the new checksum from the lockfile CHECKSUMS at #{lockfile_path}:21:17 is correct:
              1. remove the matching checksum in #{lockfile_path}:20:17
              2. run `bundle install`

            To ignore checksum security warnings, disable checksum validation with
              `bundle config set --local disable_checksum_validation true`
          MESSAGE
        end
      end
    end
  end
end
