require_relative '../../spec_helper'

describe "Float#ceil" do
  it "returns the smallest Integer greater than or equal to self" do
    -1.2.ceil.should eql( -1)
    -1.0.ceil.should eql( -1)
    0.0.ceil.should  eql( 0 )
    1.3.ceil.should  eql( 2 )
    3.0.ceil.should  eql( 3 )
    -9223372036854775808.1.ceil.should eql(-9223372036854775808)
    +9223372036854775808.1.ceil.should eql(+9223372036854775808)
  end

  ruby_version_is "2.4" do
    it "returns the smallest number greater than or equal to self with an optionally given precision" do
      2.1679.ceil(0).should   eql(3)
      214.94.ceil(-1).should  eql(220)
      7.0.ceil(1).should      eql(7.0)
      -1.234.ceil(2).should   eql(-1.23)
      5.123812.ceil(4).should eql(5.1239)
    end
  end
end
