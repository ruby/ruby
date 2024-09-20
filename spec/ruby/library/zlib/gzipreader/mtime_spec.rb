require_relative '../../../spec_helper'
require 'zlib'
require 'stringio'

describe "Zlib::GzipReader#mtime" do
  it "returns the timestamp from the Gzip header" do
    io = StringIO.new "\x1f\x8b\x08\x00\x44\x33\x22\x11\x00\xff\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    gz = Zlib::GzipReader.new(io)
    gz.mtime.to_i.should == 0x11223344
  end
end
