require_relative '../../spec_helper'

describe "ENV.store" do
  it "is an alias of ENV.[]=" do
    ENV.method(:store).should == ENV.method(:[]=)
  end
end
