require_relative '../../spec_helper'

describe "NilClass" do
  it ".allocate raises a TypeError" do
    -> do
      NilClass.allocate
    end.should raise_error(TypeError)
  end

  it ".new is undefined" do
    -> do
      NilClass.new
    end.should raise_error(NoMethodError)
  end
end
