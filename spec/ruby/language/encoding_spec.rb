# -*- encoding: us-ascii -*-
require_relative '../spec_helper'
require_relative 'fixtures/coding_us_ascii'
require_relative 'fixtures/coding_utf_8'

describe "The __ENCODING__ pseudo-variable" do
  it "is an instance of Encoding" do
    __ENCODING__.should be_kind_of(Encoding)
  end

  it "is US-ASCII by default" do
    __ENCODING__.should == Encoding::US_ASCII
  end

  it "is the evaluated strings's one inside an eval" do
    eval("__ENCODING__".dup.force_encoding("US-ASCII")).should == Encoding::US_ASCII
    eval("__ENCODING__".dup.force_encoding("BINARY")).should == Encoding::BINARY
  end

  it "is the encoding specified by a magic comment inside an eval" do
    code = "# encoding: BINARY\n__ENCODING__".dup.force_encoding("US-ASCII")
    eval(code).should == Encoding::BINARY

    code = "# encoding: us-ascii\n__ENCODING__".dup.force_encoding("BINARY")
    eval(code).should == Encoding::US_ASCII
  end

  it "is the encoding specified by a magic comment in the file" do
    CodingUS_ASCII.encoding.should == Encoding::US_ASCII
    CodingUTF_8.encoding.should == Encoding::UTF_8
  end

  it "raises a SyntaxError if assigned to" do
    -> { eval("__ENCODING__ = 1") }.should raise_error(SyntaxError)
  end
end
