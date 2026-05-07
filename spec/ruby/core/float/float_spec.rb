require_relative '../../spec_helper'

describe "Float" do
  it "includes Comparable" do
    Float.include?(Comparable).should == true
  end

  it ".allocate raises a TypeError" do
    -> do
      Float.allocate
    end.should.raise(TypeError)
  end

  it ".new is undefined" do
    -> do
      Float.new
    end.should.raise(NoMethodError)
  end
end
