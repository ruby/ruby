require_relative '../../spec_helper'

describe "ENV.length" do
  it "is an alias of ENV.size" do
    ENV.method(:length).should == ENV.method(:size)
  end
end
