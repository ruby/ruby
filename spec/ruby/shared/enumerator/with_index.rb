require_relative '../../spec_helper'

describe :enum_with_index, shared: true do

  require_relative '../../fixtures/enumerator/classes'

  before :each do
    @origin = [1, 2, 3, 4]
    @enum = @origin.to_enum
  end

  it "passes each element and its index to block" do
    a = []
    @enum.send(@method) { |o, i| a << [o, i] }
    a.should == [[1, 0], [2, 1], [3, 2], [4, 3]]
  end

  it "returns the object being enumerated when given a block" do
    @enum.send(@method) { |o, i| :glark }.should equal(@origin)
  end

  it "binds splat arguments properly" do
    acc = []
    @enum.send(@method) { |*b| c,d = b; acc << c; acc << d }
    [1, 0, 2, 1, 3, 2, 4, 3].should == acc
  end

  it "returns an enumerator if no block is supplied" do
    ewi = @enum.send(@method)
    ewi.should be_an_instance_of(Enumerator)
    ewi.to_a.should == [[1, 0], [2, 1], [3, 2], [4, 3]]
  end
end
