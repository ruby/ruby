require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#flush" do
  it "returns self" do
    io = StringIO.new("flush")
    io.flush.should equal(io)
  end
end
