require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#hash" do
  it "is provided" do
    1.respond_to?(:hash).should == true
  end

  it "is stable" do
    1.hash.should == 1.hash
  end
end

describe "Kernel#Hash" do
  before :each do
    @hash = { a: 1}
  end

  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:Hash)
  end

  it "converts nil to a Hash" do
    Hash(nil).should == {}
  end

  it "converts an empty array to a Hash" do
    Hash([]).should == {}
  end

  it "does not call #to_hash on an Hash" do
    @hash.should_not_receive(:to_hash)
    Hash(@hash).should == @hash
  end

  it "calls #to_hash to convert the argument to an Hash" do
    obj = mock("Hash(a: 1)")
    obj.should_receive(:to_hash).and_return(@hash)

    Hash(obj).should == @hash
  end

  it "raises a TypeError if it doesn't respond to #to_hash" do
    -> { Hash(mock("")) }.should.raise(TypeError)
  end

  it "raises a TypeError if #to_hash does not return an Hash" do
    obj = mock("Hash() string")
    obj.should_receive(:to_hash).and_return("string")

    -> { Hash(obj) }.should.raise(TypeError)
  end
end

describe "Kernel.Hash" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:Hash)
  end
end
