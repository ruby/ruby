require_relative '../../spec_helper'
require 'stringio'

# See redmine #1667
describe "StringIO#each_codepoint" do
  before :each do
    @io = StringIO.new("∂φ/∂x = gaîté")
    @enum = @io.each_codepoint
  end

  it "returns an Enumerator" do
    @enum.should.instance_of?(Enumerator)
  end

  it "yields each codepoint code in turn" do
    @enum.to_a.should == [8706, 966, 47, 8706, 120, 32, 61, 32, 103, 97, 238, 116, 233]
  end

  it "yields each codepoint starting from the current position" do
    @io.pos = 15
    @enum.to_a.should == [238, 116, 233]
  end

  it "raises an error if reading invalid sequence" do
    @io.pos = 1  # inside of a multibyte sequence
    -> { @enum.first }.should.raise(ArgumentError)
  end

  it "raises an IOError if not readable" do
    @io.close_read
    -> { @enum.to_a }.should.raise(IOError)

    io = StringIO.new(+"xyz", "w")
    -> { io.each_codepoint.to_a }.should.raise(IOError)
  end


  it "calls the given block" do
    r  = []
    @io.each_codepoint{|c| r << c }
    r.should == [8706, 966, 47, 8706, 120, 32, 61, 32, 103, 97, 238, 116, 233]
  end

  it "returns self" do
    @io.each_codepoint {|l| l }.should.equal?(@io)
  end
end
