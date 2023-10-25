require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#empty?" do
  it "returns true if the array has no elements" do
    [].should.empty?
    [1].should_not.empty?
    [1, 2].should_not.empty?
  end
end
