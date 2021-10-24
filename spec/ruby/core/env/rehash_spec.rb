require_relative '../../spec_helper'

describe "ENV.rehash" do
  it "returns nil" do
    ENV.rehash.should == nil
  end
end
