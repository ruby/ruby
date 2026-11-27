require_relative '../../spec_helper'

describe "ENV.filter!" do
  it "is an alias of ENV.select!" do
    ENV.method(:filter!).should == ENV.method(:select!)
  end
end

describe "ENV.filter" do
  it "is an alias of ENV.select" do
    ENV.method(:filter).should == ENV.method(:select)
  end
end
