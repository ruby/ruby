require_relative '../../spec_helper'

describe "Time#isdst" do
  it "is an alias of Time#dst?" do
    Time.instance_method(:isdst).should == Time.instance_method(:dst?)
  end
end
