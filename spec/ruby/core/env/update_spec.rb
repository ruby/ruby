require_relative '../../spec_helper'

describe "ENV.update" do
  it "is an alias of ENV.merge!" do
    ENV.method(:update).should == ENV.method(:merge!)
  end
end
