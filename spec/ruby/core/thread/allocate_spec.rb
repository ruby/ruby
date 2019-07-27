require_relative '../../spec_helper'

describe "Thread.allocate" do
  it "raises a TypeError" do
    -> {
      Thread.allocate
    }.should raise_error(TypeError)
  end
end
