require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#untrusted?" do
  it "returns the untrusted status of an object" do
    o = mock('o')
    o.untrusted?.should == false
    o.untrust
    o.untrusted?.should == true
  end

  it "has no effect on immediate values" do
    a = nil
    b = true
    c = false
    a.untrust
    b.untrust
    c.untrust
    a.untrusted?.should == false
    b.untrusted?.should == false
    c.untrusted?.should == false
  end

  it "has effect on immediate values" do
    d = 1
    -> { d.untrust }.should_not raise_error(RuntimeError)
  end
end
