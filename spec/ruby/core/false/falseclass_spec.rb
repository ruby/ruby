require_relative '../../spec_helper'

describe "FalseClass" do
  it ".allocate raises a TypeError" do
    -> do
      FalseClass.allocate
    end.should raise_error(TypeError)
  end

  it ".new is undefined" do
    -> do
      FalseClass.new
    end.should raise_error(NoMethodError)
  end
end
