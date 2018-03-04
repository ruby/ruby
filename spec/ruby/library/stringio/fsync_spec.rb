require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#fsync" do
  it "returns zero" do
    io = StringIO.new("fsync")
    io.fsync.should eql(0)
  end
end
