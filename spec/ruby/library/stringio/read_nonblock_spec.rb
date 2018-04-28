require_relative '../../spec_helper'
require "stringio"
require_relative 'shared/read'
require_relative 'shared/sysread'

describe "StringIO#read_nonblock when passed length, buffer" do
  it_behaves_like :stringio_read, :read_nonblock
end

describe "StringIO#read_nonblock when passed length" do
  it_behaves_like :stringio_read_length, :read_nonblock
end

describe "StringIO#read_nonblock when passed nil" do
  it_behaves_like :stringio_read_nil, :read_nonblock
end

describe "StringIO#read_nonblock when passed length" do
  it_behaves_like :stringio_sysread_length, :read_nonblock
end

describe "StringIO#read_nonblock" do

  it "accepts an exception option" do
    stringio = StringIO.new('foo')
    stringio.read_nonblock(3, exception: false).should == 'foo'
  end

end
