require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Method#curry" do
  it "returns a curried proc" do
    x = Object.new
    def x.foo(a,b,c); [a,b,c]; end

    c = x.method(:foo).curry
    c.should.is_a?(Proc)
    c.call(1).call(2, 3).should == [1,2,3]
  end

  describe "with optional arity argument" do
    before(:each) do
      @obj = MethodSpecs::Methods.new
    end

    it "returns a curried proc when given correct arity" do
      @obj.method(:one_req).curry(1).should.is_a?(Proc)
      @obj.method(:zero_with_splat).curry(100).should.is_a?(Proc)
      @obj.method(:two_req_with_splat).curry(2).should.is_a?(Proc)
    end

    it "raises ArgumentError when the method requires less arguments than the given arity" do
      -> { @obj.method(:zero).curry(1) }.should.raise(ArgumentError)
      -> { @obj.method(:one_req_one_opt).curry(3) }.should.raise(ArgumentError)
      -> { @obj.method(:two_req_one_opt_with_block).curry(4) }.should.raise(ArgumentError)
    end

    it "raises ArgumentError when the method requires more arguments than the given arity" do
      -> { @obj.method(:two_req_with_splat).curry(1) }.should.raise(ArgumentError)
      -> { @obj.method(:one_req).curry(0) }.should.raise(ArgumentError)
    end
  end
end
