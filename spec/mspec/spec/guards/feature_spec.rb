require 'spec_helper'
require 'mspec/guards'

describe FeatureGuard, ".enabled?" do
  it "returns true if the feature is enabled" do
    MSpec.should_receive(:feature_enabled?).with(:encoding).and_return(true)
    FeatureGuard.enabled?(:encoding).should be_true
  end

  it "returns false if the feature is not enabled" do
    MSpec.should_receive(:feature_enabled?).with(:encoding).and_return(false)
    FeatureGuard.enabled?(:encoding).should be_false
  end

  it "returns true if all the features are enabled" do
    MSpec.should_receive(:feature_enabled?).with(:one).and_return(true)
    MSpec.should_receive(:feature_enabled?).with(:two).and_return(true)
    FeatureGuard.enabled?(:one, :two).should be_true
  end

  it "returns false if any of the features are not enabled" do
    MSpec.should_receive(:feature_enabled?).with(:one).and_return(true)
    MSpec.should_receive(:feature_enabled?).with(:two).and_return(false)
    FeatureGuard.enabled?(:one, :two).should be_false
  end
end

describe Object, "#with_feature" do
  before :each do
    ScratchPad.clear

    @guard = FeatureGuard.new :encoding
    FeatureGuard.stub(:new).and_return(@guard)
  end

  it "sets the name of the guard to :with_feature" do
    with_feature(:encoding) { }
    @guard.name.should == :with_feature
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    @guard.should_receive(:match?).and_return(true)
    @guard.should_receive(:unregister)
    lambda do
      with_feature { raise Exception }
    end.should raise_error(Exception)
  end
end

describe Object, "#with_feature" do
  before :each do
    ScratchPad.clear
  end

  it "yields if the feature is enabled" do
    MSpec.should_receive(:feature_enabled?).with(:encoding).and_return(true)
    with_feature(:encoding) { ScratchPad.record :yield }
    ScratchPad.recorded.should == :yield
  end

  it "yields if all the features are enabled" do
    MSpec.should_receive(:feature_enabled?).with(:one).and_return(true)
    MSpec.should_receive(:feature_enabled?).with(:two).and_return(true)
    with_feature(:one, :two) { ScratchPad.record :yield }
    ScratchPad.recorded.should == :yield
  end

  it "does not yield if the feature is not enabled" do
    MSpec.should_receive(:feature_enabled?).with(:encoding).and_return(false)
    with_feature(:encoding) { ScratchPad.record :yield }
    ScratchPad.recorded.should be_nil
  end

  it "does not yield if any of the features are not enabled" do
    MSpec.should_receive(:feature_enabled?).with(:one).and_return(true)
    MSpec.should_receive(:feature_enabled?).with(:two).and_return(false)
    with_feature(:one, :two) { ScratchPad.record :yield }
    ScratchPad.recorded.should be_nil
  end
end
