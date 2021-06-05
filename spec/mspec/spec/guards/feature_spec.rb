require 'spec_helper'
require 'mspec/guards'

RSpec.describe FeatureGuard, ".enabled?" do
  it "returns true if the feature is enabled" do
    expect(MSpec).to receive(:feature_enabled?).with(:encoding).and_return(true)
    expect(FeatureGuard.enabled?(:encoding)).to be_truthy
  end

  it "returns false if the feature is not enabled" do
    expect(MSpec).to receive(:feature_enabled?).with(:encoding).and_return(false)
    expect(FeatureGuard.enabled?(:encoding)).to be_falsey
  end

  it "returns true if all the features are enabled" do
    expect(MSpec).to receive(:feature_enabled?).with(:one).and_return(true)
    expect(MSpec).to receive(:feature_enabled?).with(:two).and_return(true)
    expect(FeatureGuard.enabled?(:one, :two)).to be_truthy
  end

  it "returns false if any of the features are not enabled" do
    expect(MSpec).to receive(:feature_enabled?).with(:one).and_return(true)
    expect(MSpec).to receive(:feature_enabled?).with(:two).and_return(false)
    expect(FeatureGuard.enabled?(:one, :two)).to be_falsey
  end
end

RSpec.describe Object, "#with_feature" do
  before :each do
    ScratchPad.clear

    @guard = FeatureGuard.new :encoding
    allow(FeatureGuard).to receive(:new).and_return(@guard)
  end

  it "sets the name of the guard to :with_feature" do
    with_feature(:encoding) { }
    expect(@guard.name).to eq(:with_feature)
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    expect(@guard).to receive(:match?).and_return(true)
    expect(@guard).to receive(:unregister)
    expect do
      with_feature { raise Exception }
    end.to raise_error(Exception)
  end
end

RSpec.describe Object, "#with_feature" do
  before :each do
    ScratchPad.clear
  end

  it "yields if the feature is enabled" do
    expect(MSpec).to receive(:feature_enabled?).with(:encoding).and_return(true)
    with_feature(:encoding) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "yields if all the features are enabled" do
    expect(MSpec).to receive(:feature_enabled?).with(:one).and_return(true)
    expect(MSpec).to receive(:feature_enabled?).with(:two).and_return(true)
    with_feature(:one, :two) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "does not yield if the feature is not enabled" do
    expect(MSpec).to receive(:feature_enabled?).with(:encoding).and_return(false)
    with_feature(:encoding) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to be_nil
  end

  it "does not yield if any of the features are not enabled" do
    expect(MSpec).to receive(:feature_enabled?).with(:one).and_return(true)
    expect(MSpec).to receive(:feature_enabled?).with(:two).and_return(false)
    with_feature(:one, :two) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to be_nil
  end
end

RSpec.describe Object, "#without_feature" do
  before :each do
    ScratchPad.clear

    @guard = FeatureGuard.new :encoding
    allow(FeatureGuard).to receive(:new).and_return(@guard)
  end

  it "sets the name of the guard to :without_feature" do
    without_feature(:encoding) { }
    expect(@guard.name).to eq(:without_feature)
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    expect(@guard).to receive(:match?).and_return(false)
    expect(@guard).to receive(:unregister)
    expect do
      without_feature { raise Exception }
    end.to raise_error(Exception)
  end
end

RSpec.describe Object, "#without_feature" do
  before :each do
    ScratchPad.clear
  end

  it "does not yield if the feature is enabled" do
    expect(MSpec).to receive(:feature_enabled?).with(:encoding).and_return(true)
    without_feature(:encoding) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to be_nil
  end

  it "yields if the feature is disabled" do
    expect(MSpec).to receive(:feature_enabled?).with(:encoding).and_return(false)
    without_feature(:encoding) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end
end
