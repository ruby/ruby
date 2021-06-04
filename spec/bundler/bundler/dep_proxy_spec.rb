# frozen_string_literal: true

RSpec.describe Bundler::DepProxy do
  let(:dep) { Bundler::Dependency.new("rake", ">= 0") }
  subject { described_class.get_proxy(dep, Gem::Platform::RUBY) }
  let(:same) { subject }
  let(:other) { described_class.get_proxy(dep, Gem::Platform::RUBY) }
  let(:different) { described_class.get_proxy(dep, Gem::Platform::JAVA) }

  describe "#eql?" do
    it { expect(subject.eql?(same)).to be true }
    it { expect(subject.eql?(other)).to be true }
    it { expect(subject.eql?(different)).to be false }
    it { expect(subject.eql?(nil)).to be false }
    it { expect(subject.eql?("foobar")).to be false }
  end

  describe "must use factory methods" do
    it { expect { described_class.new(dep, Gem::Platform::RUBY) }.to raise_error NoMethodError }
    it { expect { subject.dup }.to raise_error NoMethodError }
    it { expect { subject.clone }.to raise_error NoMethodError }
  end

  describe "frozen" do
    if Gem.ruby_version >= Gem::Version.new("2.5.0")
      error = Object.const_get("FrozenError")
    else
      error = RuntimeError
    end
    it { expect { subject.instance_variable_set(:@__platform, {}) }.to raise_error error }
  end
end
