# frozen_string_literal: true

RSpec.describe Bundler::RemoteSpecification do
  let(:name)         { "foo" }
  let(:version)      { Gem::Version.new("1.0.0") }
  let(:platform)     { Gem::Platform::RUBY }
  let(:spec_fetcher) { double(:spec_fetcher) }

  subject { described_class.new(name, version, platform, spec_fetcher) }

  it "is Comparable" do
    expect(described_class.ancestors).to include(Comparable)
  end

  it "can match platforms" do
    expect(described_class.ancestors).to include(Bundler::MatchPlatform)
  end

  describe "#fetch_platform" do
    let(:remote_spec) { double(:remote_spec, :platform => "jruby") }

    before { allow(spec_fetcher).to receive(:fetch_spec).and_return(remote_spec) }

    it "should return the spec platform" do
      expect(subject.fetch_platform).to eq("jruby")
    end
  end

  describe "#full_name" do
    context "when platform is ruby" do
      it "should return the spec name and version" do
        expect(subject.full_name).to eq("foo-1.0.0")
      end
    end

    context "when platform is nil" do
      let(:platform) { nil }

      it "should return the spec name and version" do
        expect(subject.full_name).to eq("foo-1.0.0")
      end
    end

    context "when platform is a non-ruby platform" do
      let(:platform) { "jruby" }

      it "should return the spec name, version, and platform" do
        expect(subject.full_name).to eq("foo-1.0.0-jruby")
      end
    end
  end

  describe "#<=>" do
    let(:other_name)         { name }
    let(:other_version)      { version }
    let(:other_platform)     { platform }
    let(:other_spec_fetcher) { spec_fetcher }

    shared_examples_for "a comparison" do
      context "which exactly matches" do
        it "returns 0" do
          expect(subject <=> other).to eq(0)
        end
      end

      context "which is different by name" do
        let(:other_name) { "a" }
        it "returns 1" do
          expect(subject <=> other).to eq(1)
        end
      end

      context "which has a lower version" do
        let(:other_version) { Gem::Version.new("0.9.0") }
        it "returns 1" do
          expect(subject <=> other).to eq(1)
        end
      end

      context "which has a higher version" do
        let(:other_version) { Gem::Version.new("1.1.0") }
        it "returns -1" do
          expect(subject <=> other).to eq(-1)
        end
      end

      context "which has a different platform" do
        let(:other_platform) { Gem::Platform.new("x86-mswin32") }
        it "returns -1" do
          expect(subject <=> other).to eq(-1)
        end
      end
    end

    context "comparing another Bundler::RemoteSpecification" do
      let(:other) do
        Bundler::RemoteSpecification.new(other_name, other_version,
          other_platform, nil)
      end

      it_should_behave_like "a comparison"
    end

    context "comparing a Gem::Specification" do
      let(:other) do
        Gem::Specification.new(other_name, other_version).tap do |s|
          s.platform = other_platform
        end
      end

      it_should_behave_like "a comparison"
    end

    context "comparing a non sortable object" do
      let(:other) { Object.new }
      let(:remote_spec) { double(:remote_spec, :platform => "jruby") }

      before do
        allow(spec_fetcher).to receive(:fetch_spec).and_return(remote_spec)
        allow(remote_spec).to receive(:<=>).and_return(nil)
      end

      it "should use default object comparison" do
        expect(subject <=> other).to eq(nil)
      end
    end
  end

  describe "#__swap__" do
    let(:spec) { double(:spec, :dependencies => []) }
    let(:new_spec) { double(:new_spec, :dependencies => [], :runtime_dependencies => []) }

    before { subject.instance_variable_set(:@_remote_specification, spec) }

    it "should replace remote specification with the passed spec" do
      expect(subject.instance_variable_get(:@_remote_specification)).to be(spec)
      subject.__swap__(new_spec)
      expect(subject.instance_variable_get(:@_remote_specification)).to be(new_spec)
    end
  end

  describe "#sort_obj" do
    context "when platform is ruby" do
      it "should return a sorting delegate array with name, version, and -1" do
        expect(subject.sort_obj).to match_array(["foo", version, -1])
      end
    end

    context "when platform is not ruby" do
      let(:platform) { "jruby" }

      it "should return a sorting delegate array with name, version, and 1" do
        expect(subject.sort_obj).to match_array(["foo", version, 1])
      end
    end
  end

  describe "method missing" do
    context "and is present in Gem::Specification" do
      let(:remote_spec) { double(:remote_spec, :authors => "abcd") }

      before do
        allow(subject).to receive(:_remote_specification).and_return(remote_spec)
        expect(subject.methods.map(&:to_sym)).not_to include(:authors)
      end

      it "should send through to Gem::Specification" do
        expect(subject.authors).to eq("abcd")
      end
    end
  end

  describe "respond to missing?" do
    context "and is present in Gem::Specification" do
      let(:remote_spec) { double(:remote_spec, :authors => "abcd") }

      before do
        allow(subject).to receive(:_remote_specification).and_return(remote_spec)
        expect(subject.methods.map(&:to_sym)).not_to include(:authors)
      end

      it "should send through to Gem::Specification" do
        expect(subject.respond_to?(:authors)).to be_truthy
      end
    end
  end
end
