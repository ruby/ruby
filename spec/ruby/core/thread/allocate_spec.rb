require_relative '../../spec_helper'

describe "Thread.allocate" do
  it "raises a TypeError" do
    lambda {
      Thread.allocate
    }.should raise_error(TypeError)
  end
end
