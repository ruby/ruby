# frozen_string_literal: true

RSpec.describe Bundler::EndpointSpecification do
  let(:name)         { "foo" }
  let(:version)      { "1.0.0" }
  let(:platform)     { Gem::Platform::RUBY }
  let(:dependencies) { [] }
  let(:metadata)     { nil }

  subject(:spec) { described_class.new(name, version, platform, dependencies, metadata) }

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
            and(a_string_including('The metadata was {"rubygems"=>">\n"}'))
        )
      end
    end
  end

  it "supports equality comparison" do
    other_spec = described_class.new("bar", version, platform, dependencies, metadata)
    expect(spec).to eql(spec)
    expect(spec).to_not eql(other_spec)
  end
end
