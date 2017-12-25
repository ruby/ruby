require File.expand_path('../../../spec_helper', __FILE__)
require 'thread'

describe "ConditionVariable#marshal_dump" do
  it "raises a TypeError" do
    cv = ConditionVariable.new
    -> { cv.marshal_dump }.should raise_error(TypeError, /can't dump/)
  end
end
