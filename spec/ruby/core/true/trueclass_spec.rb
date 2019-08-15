require_relative '../../spec_helper'

describe "TrueClass" do
  it ".allocate raises a TypeError" do
    -> do
      TrueClass.allocate
    end.should raise_error(TypeError)
  end

  it ".new is undefined" do
    -> do
      TrueClass.new
    end.should raise_error(NoMethodError)
  end
end
