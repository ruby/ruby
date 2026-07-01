require_relative '../../spec_helper'

describe "Hash#to_s" do
  it "is an alias of Hash#inspect" do
    Hash.instance_method(:to_s).should == Hash.instance_method(:inspect)
  end
end
