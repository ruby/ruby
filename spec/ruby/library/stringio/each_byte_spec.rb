require_relative '../../spec_helper'
require 'stringio'

describe "StringIO#each_byte" do
  before :each do
    @io = StringIO.new("xyz")
  end

  it "yields each character code in turn" do
    seen = []
    @io.each_byte { |b| seen << b }
    seen.should == [120, 121, 122]
  end

  it "updates the position before each yield" do
    seen = []
    @io.each_byte { |b| seen << @io.pos }
    seen.should == [1, 2, 3]
  end

  it "does not yield if the current position is out of bounds" do
    @io.pos = 1000
    seen = nil
    @io.each_byte { |b| seen = b }
    seen.should == nil
  end

  it "returns self" do
    @io.each_byte {}.should.equal?(@io)
  end

  it "returns an Enumerator when passed no block" do
    enum = @io.each_byte
    enum.instance_of?(Enumerator).should == true

    seen = []
    enum.each { |b| seen << b }
    seen.should == [120, 121, 122]
  end
end

describe "StringIO#each_byte when self is not readable" do
  it "raises an IOError" do
    io = StringIO.new(+"xyz", "w")
    -> { io.each_byte { |b| b } }.should.raise(IOError)

    io = StringIO.new("xyz")
    io.close_read
    -> { io.each_byte { |b| b } }.should.raise(IOError)
  end
end
