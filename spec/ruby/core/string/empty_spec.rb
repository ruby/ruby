require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#empty?" do
  it "returns true if the string has a length of zero" do
    "hello".should_not.empty?
    " ".should_not.empty?
    "\x00".should_not.empty?
    "".should.empty?
    StringSpecs::MyString.new("").should.empty?
  end
end
