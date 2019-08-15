require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#binmode" do
  it "returns self" do
    io = StringIO.new("example")
    io.binmode.should equal(io)
  end
end
