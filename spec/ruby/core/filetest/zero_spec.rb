require_relative '../../spec_helper'

describe "FileTest.zero?" do
  it "is an alias of FileTest.empty?" do
    FileTest.method(:zero?).should == FileTest.method(:empty?)
  end
end
