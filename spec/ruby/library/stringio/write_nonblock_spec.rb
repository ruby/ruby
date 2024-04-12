require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/write'

describe "StringIO#write_nonblock when passed [Object]" do
  it_behaves_like :stringio_write, :write_nonblock
end

describe "StringIO#write_nonblock when passed [String]" do
  it_behaves_like :stringio_write_string, :write_nonblock

  it "accepts :exception option" do
    io = StringIO.new(+"12345", "a")
    io.write_nonblock("67890", exception: true)
    io.string.should == "1234567890"
  end
end

describe "StringIO#write_nonblock when self is not writable" do
  it_behaves_like :stringio_write_not_writable, :write_nonblock
end

describe "StringIO#write_nonblock when in append mode" do
  it_behaves_like :stringio_write_append, :write_nonblock
end
