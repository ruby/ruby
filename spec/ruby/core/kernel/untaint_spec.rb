require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#untaint" do
  it "returns self" do
    o = Object.new
    o.untaint.should equal(o)
  end

  it "clears the tainted bit" do
    o = Object.new.taint
    o.untaint
    o.tainted?.should == false
  end

  it "raises #{frozen_error_class} on a tainted, frozen object" do
    o = Object.new.taint.freeze
    lambda { o.untaint }.should raise_error(frozen_error_class)
  end

  it "does not raise an error on an untainted, frozen object" do
    o = Object.new.freeze
    o.untaint.should equal(o)
  end
end
