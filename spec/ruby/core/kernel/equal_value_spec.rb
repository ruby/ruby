require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#==" do
  it "returns true only if obj and other are the same object" do
    o1 = mock('o1')
    o2 = mock('o2')
    (o1 == o1).should == true
    (o2 == o2).should == true
    (o1 == o2).should == false
    (nil == nil).should == true
    (o1 == nil).should == false
    (nil == o2).should == false
  end
end
