require_relative '../../spec_helper'

describe "ObjectSpace.garbage_collect" do

  it "can be invoked without any exceptions" do
    -> { ObjectSpace.garbage_collect }.should_not raise_error
  end

  it "accepts keyword arguments" do
    ObjectSpace.garbage_collect(full_mark: true, immediate_sweep: true).should == nil
  end

  it "ignores the supplied block" do
    -> { ObjectSpace.garbage_collect {} }.should_not raise_error
  end

  it "always returns nil" do
    ObjectSpace.garbage_collect.should == nil
    ObjectSpace.garbage_collect.should == nil
  end

end
