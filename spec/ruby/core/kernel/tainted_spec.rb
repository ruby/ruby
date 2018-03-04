require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#tainted?" do
  it "returns true if Object is tainted" do
    o = mock('o')
    p = mock('p')
    p.taint
    o.tainted?.should == false
    p.tainted?.should == true
  end
end
