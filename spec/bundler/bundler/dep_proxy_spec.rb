# frozen_string_literal: true

RSpec.describe Bundler::DepProxy do
  let(:dep) { Bundler::Dependency.new("rake", ">= 0") }
  subject { described_class.new(dep, Gem::Platform::RUBY) }
  let(:same) { subject }
  let(:other) { subject.dup }
  let(:different) { described_class.new(dep, Gem::Platform::JAVA) }

  describe "#eql?" do
    it { expect(subject.eql?(same)).to be true }
    it { expect(subject.eql?(other)).to be true }
    it { expect(subject.eql?(different)).to be false }
    it { expect(subject.eql?(nil)).to be false }
    it { expect(subject.eql?("foobar")).to be false }
  end

  describe "#hash" do
    it { expect(subject.hash).to eq(same.hash) }
    it { expect(subject.hash).to eq(other.hash) }
  end
end
