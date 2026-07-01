require_relative '../../spec_helper'

describe "File.zero?" do
  it "is an alias of File.empty?" do
    File.method(:zero?).should == File.method(:empty?)
  end
end
