# frozen_string_literal: true

RSpec.describe Bundler::EndpointSpecification do
  let(:name)         { "foo" }
  let(:version)      { "1.0.0" }
  let(:suffix)       { Gem::Platform::RUBY }
  let(:dependencies) { [] }
  let(:spec_fetcher) { double(:spec_fetcher) }
  let(:metadata)     { nil }

  subject(:spec) { described_class.new(name, version, suffix, spec_fetcher, dependencies, metadata) }

  def with_tz(tz)
    orig_tz = ENV["TZ"]
    ENV["TZ"] = tz
    yield
  ensure
    ENV["TZ"] = orig_tz
  end

  describe "#build_dependency" do
    let(:name)           { "foo" }
    let(:requirement1)   { "~> 1.1" }
    let(:requirement2)   { ">= 1.1.7" }

    it "should return a Gem::Dependency" do
      expect(subject.send(:build_dependency, name, [requirement1, requirement2])).
        to eq(Gem::Dependency.new(name, requirement1, requirement2))
    end

    context "when an ArgumentError occurs" do
      before do
        allow(Gem::Dependency).to receive(:new).with(name, [requirement1, requirement2]) {
          raise ArgumentError.new("Some error occurred")
        }
      end

      it "should raise the original error" do
        expect { subject.send(:build_dependency, name, [requirement1, requirement2]) }.to raise_error(
          ArgumentError, "Some error occurred"
        )
      end
    end
  end

  describe "#parse_metadata" do
    context "when a content-addressed suffix has platform metadata" do
      let(:suffix) { "abc1234567" }
      let(:metadata) { { "platform" => ["arm64-darwin"], "ruby" => ["~> 3.4.0"] } }

      it "uses the platform from the metadata" do
        expect(spec.platform).to eq(Gem::Platform.new("arm64-darwin"))
        expect(spec.content_address).to eq("abc1234567")
      end

      it "includes the content address in full_name" do
        expect(spec.full_name).to eq("foo-1.0.0-abc1234567")
      end
    end

    context "when the suffix is an ordinary platform" do
      let(:suffix) { "x86_64-linux" }

      it "uses the suffix as the platform without a content address" do
        expect(spec.platform).to eq(Gem::Platform.new("x86_64-linux"))
        expect(spec.content_address).to be_nil
      end
    end

    context "when a content-addressed suffix has no platform metadata" do
      let(:suffix) { "abc1234567" }

      it "treats the suffix as a platform without a content address" do
        expect(spec.content_address).to be_nil
      end
    end

    context "when a content-addressed suffix has no ruby metadata" do
      let(:suffix) { "abc1234567" }
      let(:metadata) { { "platform" => ["arm64-darwin"] } }

      it "does not assign a content address" do
        expect(spec.content_address).to be_nil
      end
    end

    context "when a content-addressed suffix has non-ABI ruby metadata" do
      let(:suffix) { "abc1234567" }
      let(:metadata) { { "platform" => ["arm64-darwin"], "ruby" => [">= 3.0"] } }

      it "does not assign a content address" do
        expect(spec.content_address).to be_nil
      end
    end

    context "when the metadata has malformed requirements" do
      let(:metadata) { { "rubygems" => ">\n" } }
      it "raises a helpful error message" do
        expect { subject }.to raise_error(
          Bundler::GemspecError,
          a_string_including("There was an error parsing the metadata for the gem foo (1.0.0)").
            and(a_string_including("The metadata was #{{ "rubygems" => ">\n" }.inspect}"))
        )
      end
    end

    context "when the metadata has created_at" do
      let(:metadata) { { "created_at" => ["2026-05-12T10:00:00Z"] } }

      it "parses created_at as a Time" do
        expect(subject.created_at).to eq(Time.utc(2026, 5, 12, 10, 0, 0))
      end
    end

    context "when the metadata has a string created_at (older rubygems shape)" do
      let(:metadata) { { "created_at" => "2026-05-12T10:00:00Z" } }

      it "still parses created_at" do
        expect(subject.created_at).to eq(Time.utc(2026, 5, 12, 10, 0, 0))
      end
    end

    context "when created_at has no time zone offset" do
      let(:metadata) { { "created_at" => "2026-05-12T10:00:00" } }

      it "is interpreted as UTC regardless of the local time zone" do
        with_tz("Asia/Tokyo") do
          expect(subject.created_at).to eq(Time.utc(2026, 5, 12, 10, 0, 0))
        end
      end
    end

    context "when created_at has an explicit offset" do
      let(:metadata) { { "created_at" => "2026-05-12T10:00:00+02:00" } }

      it "keeps the offset" do
        expect(subject.created_at).to eq(Time.utc(2026, 5, 12, 8, 0, 0))
      end
    end

    context "when created_at is truncated (older rubygems splits on colons)" do
      let(:metadata) { { "created_at" => "2026-05-12T10" } }

      it "leaves created_at as nil instead of raising" do
        expect(subject.created_at).to be_nil
      end
    end

    context "when created_at has a year that overflows Float arithmetic" do
      let(:metadata) { { "created_at" => ["#{"9" * 400}-01-01T00:00:00Z"] } }

      it "leaves created_at as nil" do
        expect(subject.created_at).to be_nil
      end
    end

    context "when the metadata has an empty checksum value" do
      let(:metadata) { { "checksum" => [] } }

      it "leaves checksum as nil without raising" do
        expect(subject.checksum).to be_nil
      end
    end

    context "when the metadata has a nil checksum value" do
      let(:metadata) { { "checksum" => nil } }

      it "leaves checksum as nil without raising" do
        expect(subject.checksum).to be_nil
      end
    end

    context "when the metadata has an invalid checksum value" do
      let(:metadata) { { "checksum" => ["xyz"] } }
      let(:spec_fetcher) { double(:spec_fetcher, uri: "https://rubygems.org") }

      it "raises an error mentioning the invalid checksum" do
        expect { subject }.to raise_error(
          Bundler::GemspecError,
          a_string_including("Invalid checksum for foo-1.0.0")
        )
      end
    end

    context "when the metadata has no created_at" do
      let(:metadata) { { "checksum" => ["abc"] } }
      let(:spec_fetcher) { double(:spec_fetcher, uri: "https://rubygems.org") }

      it "leaves created_at as nil" do
        allow(Bundler::Checksum).to receive(:from_api).and_return(nil)
        expect(subject.created_at).to be_nil
      end
    end

    context "when the metadata is nil" do
      it "leaves created_at as nil" do
        expect(subject.created_at).to be_nil
      end
    end
  end

  describe "#required_ruby_version" do
    context "required_ruby_version is already set on endpoint specification" do
      let(:metadata) { { "ruby" => [">= 3.0"] } }

      it "returns the value from metadata without fetching the remote spec" do
        expect(spec_fetcher).not_to receive(:fetch_spec)
        expect(spec.required_ruby_version).to eq(Gem::Requirement.new(">= 3.0"))
      end
    end

    it "returns nil when not set on endpoint specification and metadata is nil" do
      expect(spec_fetcher).not_to receive(:fetch_spec)
      expect(spec.required_ruby_version).to be_nil
    end

    it "loads required_ruby_version from the remote spec via matches_current_ruby?" do
      remote_spec = double(:remote_spec, required_ruby_version: Gem::Requirement.new(">= 3.0"), required_rubygems_version: nil)
      allow(spec_fetcher).to receive(:fetch_spec).and_return(remote_spec)

      spec.matches_current_ruby?
      expect(spec.required_ruby_version).to eq(Gem::Requirement.new(">= 3.0"))
    end
  end

  it "supports equality comparison" do
    remote_spec = double(:remote_spec, required_ruby_version: nil, required_rubygems_version: nil)
    allow(spec_fetcher).to receive(:fetch_spec).and_return(remote_spec)
    other_spec = described_class.new("bar", version, suffix, spec_fetcher, dependencies, metadata)
    expect(spec).to eql(spec)
    expect(spec).to_not eql(other_spec)
  end
end
