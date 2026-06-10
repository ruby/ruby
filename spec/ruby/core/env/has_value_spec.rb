require_relative '../../spec_helper'

describe "ENV.has_value?" do
  it "is an alias of ENV.value?" do
    ENV.method(:has_value?).should == ENV.method(:value?)
  end
end
