require_relative '../../spec_helper'

describe "Symbol#succ" do
  it "returns a successor" do
    :abcd.succ.should == :abce
    :THX1138.succ.should == :THX1139
  end

  it "propagates a 'carry'" do
    :"1999zzz".succ.should == :"2000aaa"
    :ZZZ9999.succ.should == :AAAA0000
  end

  it "increments non-alphanumeric characters when no alphanumeric characters are present" do
    :"<<koala>>".succ.should == :"<<koalb>>"
    :"***".succ.should == :"**+"
  end
end
