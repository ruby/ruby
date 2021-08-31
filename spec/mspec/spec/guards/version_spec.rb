require 'spec_helper'
require 'mspec/guards'

# The VersionGuard specifies a version of Ruby with a String of
# the form: v = 'major.minor.tiny'.
#
# A VersionGuard instance can be created with a single String,
# which means any version >= each component of v.
# Or, the guard can be created with a Range, a..b, or a...b,
# where a, b are of the same form as v. The meaning of the Range
# is as typically understood: a..b means v >= a and v <= b;
# a...b means v >= a and v < b.

RSpec.describe VersionGuard, "#match?" do
  before :each do
    hide_deprecation_warnings
    @current = '1.8.6'
  end

  it "returns true when the argument is equal to RUBY_VERSION" do
    expect(VersionGuard.new(@current, '1.8.6').match?).to eq(true)
  end

  it "returns true when the argument is less than RUBY_VERSION" do
    expect(VersionGuard.new(@current, '1.8').match?).to eq(true)
    expect(VersionGuard.new(@current, '1.8.5').match?).to eq(true)
  end

  it "returns false when the argument is greater than RUBY_VERSION" do
    expect(VersionGuard.new(@current, '1.8.7').match?).to eq(false)
    expect(VersionGuard.new(@current, '1.9.2').match?).to eq(false)
  end

  it "returns true when the argument range includes RUBY_VERSION" do
    expect(VersionGuard.new(@current, '1.8.5'..'1.8.7').match?).to eq(true)
    expect(VersionGuard.new(@current, '1.8'..'1.9').match?).to eq(true)
    expect(VersionGuard.new(@current, '1.8'...'1.9').match?).to eq(true)
    expect(VersionGuard.new(@current, '1.8'..'1.8.6').match?).to eq(true)
    expect(VersionGuard.new(@current, '1.8.5'..'1.8.6').match?).to eq(true)
    expect(VersionGuard.new(@current, ''...'1.8.7').match?).to eq(true)
  end

  it "returns false when the argument range does not include RUBY_VERSION" do
    expect(VersionGuard.new(@current, '1.8.7'..'1.8.9').match?).to eq(false)
    expect(VersionGuard.new(@current, '1.8.4'..'1.8.5').match?).to eq(false)
    expect(VersionGuard.new(@current, '1.8.4'...'1.8.6').match?).to eq(false)
    expect(VersionGuard.new(@current, '1.8.5'...'1.8.6').match?).to eq(false)
    expect(VersionGuard.new(@current, ''...'1.8.6').match?).to eq(false)
  end
end

RSpec.describe Object, "#ruby_version_is" do
  before :each do
    @guard = VersionGuard.new '1.2.3', 'x.x.x'
    allow(VersionGuard).to receive(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "yields when #match? returns true" do
    allow(@guard).to receive(:match?).and_return(true)
    ruby_version_is('x.x.x') { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "does not yield when #match? returns false" do
    allow(@guard).to receive(:match?).and_return(false)
    ruby_version_is('x.x.x') { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end

  it "returns what #match? returns when no block is given" do
    allow(@guard).to receive(:match?).and_return(true)
    expect(ruby_version_is('x.x.x')).to eq(true)
    allow(@guard).to receive(:match?).and_return(false)
    expect(ruby_version_is('x.x.x')).to eq(false)
  end

  it "sets the name of the guard to :ruby_version_is" do
    ruby_version_is("") { }
    expect(@guard.name).to eq(:ruby_version_is)
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    expect(@guard).to receive(:match?).and_return(true)
    expect(@guard).to receive(:unregister)
    expect do
      ruby_version_is("") { raise Exception }
    end.to raise_error(Exception)
  end
end

RSpec.describe Object, "#version_is" do
  before :each do
    hide_deprecation_warnings
  end

  it "returns the expected values" do
    expect(version_is('1.2.3', '1.2.2')).to eq(true)
    expect(version_is('1.2.3', '1.2.3')).to eq(true)
    expect(version_is('1.2.3', '1.2.4')).to eq(false)

    expect(version_is('1.2.3', '1')).to eq(true)
    expect(version_is('1.2.3', '1.0')).to eq(true)
    expect(version_is('1.2.3', '2')).to eq(false)
    expect(version_is('1.2.3', '2.0')).to eq(false)

    expect(version_is('1.2.3', '1.2.2'..'1.2.4')).to eq(true)
    expect(version_is('1.2.3', '1.2.2'..'1.2.3')).to eq(true)
    expect(version_is('1.2.3', '1.2.2'...'1.2.3')).to eq(false)
    expect(version_is('1.2.3', '1.2.3'..'1.2.4')).to eq(true)
  end
end
