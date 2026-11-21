require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#gets" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:gets)
  end

  it "calls ARGF.gets" do
    ARGF.should_receive(:gets).and_return("spec")
    gets.should == "spec"
  end
end

describe "Kernel.gets" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:gets)
  end
end
