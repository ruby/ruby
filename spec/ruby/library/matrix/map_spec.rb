require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Matrix#map" do
  before :all do
    @m = Matrix[ [1, 2], [1, 2] ]
  end

  it "returns an instance of Matrix" do
    @m.map{|n| n * 2 }.should.is_a?(Matrix)
  end

  it "returns a Matrix where each element is the result of the block" do
    @m.map { |n| n * 2 }.should == Matrix[ [2, 4], [2, 4] ]
  end

  it "returns an enumerator if no block is given" do
    @m.map.should.instance_of?(Enumerator)
  end

  describe "for a subclass of Matrix" do
    it "returns an instance of that subclass" do
      MatrixSub.ins.map{1}.should.instance_of?(MatrixSub)
    end
  end
end
