require_relative '../../spec_helper'

describe "Marshal.restore" do
  it "is an alias of Marshal.load" do
    Marshal.method(:restore).should == Marshal.method(:load)
  end
end
