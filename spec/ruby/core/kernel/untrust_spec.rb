require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)

describe "Kernel#untrust" do
  it "returns self" do
    o = Object.new
    o.untrust.should equal(o)
  end

  it "sets the untrusted bit" do
    o = Object.new
    o.untrust
    o.untrusted?.should == true
  end

  it "raises #{frozen_error_class} on a trusted, frozen object" do
    o = Object.new.freeze
    lambda { o.untrust }.should raise_error(frozen_error_class)
  end

  it "does not raise an error on an untrusted, frozen object" do
    o = Object.new.untrust.freeze
    o.untrust.should equal(o)
  end
end
