require_relative '../../../spec_helper'
require 'stringio'
require 'zlib'

describe "Zlib::GzipReader#each_char" do

  before :each do
    @data = '12345abcde'
    @zip = [31, 139, 8, 0, 44, 220, 209, 71, 0, 3, 51, 52, 50, 54, 49, 77,
            76, 74, 78, 73, 5, 0, 157, 5, 0, 36, 10, 0, 0, 0].pack('C*')

    @io = StringIO.new @zip
    ScratchPad.clear
  end

  it "calls the given block for each char in the stream, passing the char as an argument" do
    gz = Zlib::GzipReader.new @io

    ScratchPad.record []
    gz.each_char { |b| ScratchPad << b }

    ScratchPad.recorded.should == ["1", "2", "3", "4", "5", "a", "b", "c", "d", "e"]
  end

  it "returns an enumerator, which yields each char in the stream, when no block is passed" do
    gz = Zlib::GzipReader.new @io
    enum = gz.each_char

    ScratchPad.record []
    while true
      begin
        ScratchPad << enum.next
      rescue StopIteration
        break
      end
    end

    ScratchPad.recorded.should == ["1", "2", "3", "4", "5", "a", "b", "c", "d", "e"]
  end

  it "increments position before calling the block" do
    gz = Zlib::GzipReader.new @io

    i = 1
    gz.each_char do |ignore|
      gz.pos.should == i
      i += 1
    end
  end

end
