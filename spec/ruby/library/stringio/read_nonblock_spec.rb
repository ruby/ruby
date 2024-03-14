require_relative '../../spec_helper'
require "stringio"
require_relative 'shared/read'
require_relative 'shared/sysread'

describe "StringIO#read_nonblock when passed length, buffer" do
  it_behaves_like :stringio_read, :read_nonblock

  it "accepts :exception option" do
    io = StringIO.new("example")
    io.read_nonblock(3, buffer = +"", exception: true)
    buffer.should == "exa"
  end
end

describe "StringIO#read_nonblock when passed length" do
  it_behaves_like :stringio_read_length, :read_nonblock

  it "accepts :exception option" do
    io = StringIO.new("example")
    io.read_nonblock(3, exception: true).should == "exa"
  end
end

describe "StringIO#read_nonblock when passed nil" do
  it_behaves_like :stringio_read_nil, :read_nonblock
end

describe "StringIO#read_nonblock when passed length" do
  it_behaves_like :stringio_sysread_length, :read_nonblock
end

describe "StringIO#read_nonblock" do

  it "accepts an exception option" do
    stringio = StringIO.new(+'foo')
    stringio.read_nonblock(3, exception: false).should == 'foo'
  end

  context "when exception option is set to false" do
    context "when the end is reached" do
      it "returns nil" do
        stringio = StringIO.new(+'')
        stringio << "hello"
        stringio.rewind

        stringio.read_nonblock(5).should == "hello"
        stringio.read_nonblock(5, exception: false).should be_nil
      end
    end
  end

end
