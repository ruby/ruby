# frozen_string_literal: true

RSpec.describe Bundler::EndpointSpecification do
  let(:name)         { "foo" }
  let(:version)      { "1.0.0" }
  let(:platform)     { Gem::Platform::RUBY }
  let(:dependencies) { [] }
  let(:spec_fetcher) { double(:spec_fetcher) }
  let(:metadata)     { nil }

  subject(:spec) { described_class.new(name, version, platform, spec_fetcher, dependencies, metadata) }

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
  end

  describe "#required_ruby_version" do
    context "required_ruby_version is already set on endpoint specification" do
      existing_value = "already set value"
      let(:required_ruby_version) { existing_value }

      it "should return the current value when already set on endpoint specification" do
        expect(spec.required_ruby_version). eql?(existing_value)
      end
    end

    it "should return the remote spec value when not set on endpoint specification and remote spec has one" do
      remote_value = "remote_value"
      remote_spec = double(:remote_spec, required_ruby_version: remote_value, required_rubygems_version: nil)
      allow(spec_fetcher).to receive(:fetch_spec).and_return(remote_spec)

      expect(spec.required_ruby_version). eql?(remote_value)
    end

    it "should use the default Gem Requirement value when not set on endpoint specification and not set on remote spec" do
      remote_spec = double(:remote_spec, required_ruby_version: nil, required_rubygems_version: nil)
      allow(spec_fetcher).to receive(:fetch_spec).and_return(remote_spec)
      expect(spec.required_ruby_version). eql?(Gem::Requirement.default)
    end
  end

  it "supports equality comparison" do
    remote_spec = double(:remote_spec, required_ruby_version: nil, required_rubygems_version: nil)
    allow(spec_fetcher).to receive(:fetch_spec).and_return(remote_spec)
    other_spec = described_class.new("bar", version, platform, spec_fetcher, dependencies, metadata)
    expect(spec).to eql(spec)
    expect(spec).to_not eql(other_spec)
  end
end
