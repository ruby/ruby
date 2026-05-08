require_relative '../../spec_helper'

describe "ConditionVariable#marshal_dump" do
  it "raises a TypeError" do
    cv = ConditionVariable.new
    -> { cv.marshal_dump }.should.raise(TypeError, /can't dump/)
  end
end
