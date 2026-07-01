require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#fcntl" do
  it "raises a NotImplementedError" do
    -> { StringIO.new("boom").fcntl }.should.raise(NotImplementedError)
  end
end
