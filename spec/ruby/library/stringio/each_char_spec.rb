require_relative '../../spec_helper'
require 'stringio'

describe "StringIO#each_char" do
  before :each do
    @io = StringIO.new("xyz äöü")
  end

  it "yields each character code in turn" do
    seen = []
    @io.each_char { |c| seen << c }
    seen.should == ["x", "y", "z", " ", "ä", "ö", "ü"]
  end

  it "returns self" do
    @io.each_char {}.should.equal?(@io)
  end

  it "returns an Enumerator when passed no block" do
    enum = @io.each_char
    enum.instance_of?(Enumerator).should == true

    seen = []
    enum.each { |c| seen << c }
    seen.should == ["x", "y", "z", " ", "ä", "ö", "ü"]
  end
end

describe "StringIO#each_char when self is not readable" do
  it "raises an IOError" do
    io = StringIO.new(+"xyz", "w")
    -> { io.each_char { |b| b } }.should.raise(IOError)

    io = StringIO.new("xyz")
    io.close_read
    -> { io.each_char { |b| b } }.should.raise(IOError)
  end
end
