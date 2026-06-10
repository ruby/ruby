require_relative '../../spec_helper'

describe "Hash#each" do
  it "is an alias of Hash#each_pair" do
    Hash.instance_method(:each).should == Hash.instance_method(:each_pair)
  end
end
