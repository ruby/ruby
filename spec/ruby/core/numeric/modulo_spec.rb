require_relative '../../spec_helper'

describe "Numeric#modulo" do
  it "is an alias of Numeric#%" do
    Numeric.instance_method(:modulo).should == Numeric.instance_method(:%)
  end
end

describe "Numeric#%" do
  it "returns self - other * self.div(other)" do
    s = mock_numeric('self')
    o = mock_numeric('other')
    n3 = mock_numeric('n3')
    n4 = mock_numeric('n4')
    n5 = mock_numeric('n5')
    s.should_receive(:div).with(o).and_return(n3)
    o.should_receive(:*).with(n3).and_return(n4)
    s.should_receive(:-).with(n4).and_return(n5)
    (s % o).should == n5
  end
end
