require_relative '../../spec_helper'

describe "Regexp#==" do
  it "is true if self and other have the same pattern" do
    (/abc/ == /abc/).should == true
    (/abc/ == /abd/).should == false
  end

  not_supported_on :opal do
    it "is true if self and other have the same character set code" do
      (/abc/ == /abc/x).should == false
      (/abc/x == /abc/x).should == true
      (/abc/u == /abc/n).should == false
      (/abc/u == /abc/u).should == true
      (/abc/n == /abc/n).should == true
    end
  end

  it "is true if other has the same #casefold? values" do
    (/abc/ == /abc/i).should == false
    (/abc/i == /abc/i).should == true
  end

  not_supported_on :opal do
    it "is true if self does not specify /n option and other does" do
      (// == //n).should == true
    end

    it "is true if self specifies /n option and other does not" do
      (//n == //).should == true
    end
  end
end
