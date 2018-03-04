require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#format" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:format)
  end
end

describe "Kernel.format" do
  it "is accessible as a module function" do
    Kernel.format("%s", "hello").should == "hello"
  end
end
