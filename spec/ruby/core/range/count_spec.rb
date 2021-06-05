require_relative '../../spec_helper'

describe "Range#count" do
  ruby_version_is "2.7" do
    it "returns Infinity for beginless ranges without arguments or blocks" do
      inf = Float::INFINITY
      eval("('a'...)").count.should == inf
      eval("(7..)").count.should == inf
      eval("(...'a')").count.should == inf
      eval("(...nil)").count.should == inf
      eval("(..10.0)").count.should == inf
    end
  end
end
