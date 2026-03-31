require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#eos?" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "returns true if the scan pointer is at the end of the string" do
    @s.terminate
    @s.should.eos?

    s = StringScanner.new('')
    s.should.eos?
  end

  it "returns false if the scan pointer is not at the end of the string" do
    @s.should_not.eos?
  end
end
