require_relative '../../spec_helper'

describe "Hash#key_set" do

  it "returns a set with hash keys as elements" do
    {a: 2, b: 3}.key_set.should == Set.new([:a, :b])
  end
end
