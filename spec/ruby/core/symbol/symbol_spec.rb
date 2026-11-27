require_relative '../../spec_helper'

describe "Symbol" do
  it "includes Comparable" do
    Symbol.include?(Comparable).should == true
  end

  it ".allocate raises a TypeError" do
    -> do
      Symbol.allocate
    end.should.raise(TypeError)
  end

  it ".new is undefined" do
    -> do
      Symbol.new
    end.should.raise(NoMethodError)
  end
end
