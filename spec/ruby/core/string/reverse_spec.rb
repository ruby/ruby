# encoding: utf-8

require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#reverse" do
  it "returns a new string with the characters of self in reverse order" do
    "stressed".reverse.should == "desserts"
    "m".reverse.should == "m"
    "".reverse.should == ""
  end

  it "taints the result if self is tainted" do
    "".taint.reverse.tainted?.should == true
    "m".taint.reverse.tainted?.should == true
  end

  with_feature :encoding do
    it "reverses a string with multi byte characters" do
      "微軟正黑體".reverse.should == "體黑正軟微"
    end
  end

end

describe "String#reverse!" do
  it "reverses self in place and always returns self" do
    a = "stressed"
    a.reverse!.should equal(a)
    a.should == "desserts"

    "".reverse!.should == ""
  end

  it "raises a #{frozen_error_class} on a frozen instance that is modified" do
    lambda { "anna".freeze.reverse!  }.should raise_error(frozen_error_class)
    lambda { "hello".freeze.reverse! }.should raise_error(frozen_error_class)
  end

  # see [ruby-core:23666]
  it "raises a #{frozen_error_class} on a frozen instance that would not be modified" do
    lambda { "".freeze.reverse! }.should raise_error(frozen_error_class)
  end

  with_feature :encoding do
    it "reverses a string with multi byte characters" do
      str = "微軟正黑體"
      str.reverse!
      str.should == "體黑正軟微"
    end
  end
end
