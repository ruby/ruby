require_relative 'spec_helper'

describe "ENV.each" do
  it "is an alias of ENV.each_pair" do
    ENV.method(:each).should == ENV.method(:each_pair)
  end
end
