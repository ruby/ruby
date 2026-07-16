require_relative '../../spec_helper'

describe "Hash#update" do
  it "is an alias of Hash#merge!" do
    Hash.instance_method(:update).should == Hash.instance_method(:merge!)
  end
end
