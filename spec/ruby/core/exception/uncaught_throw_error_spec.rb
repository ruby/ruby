require_relative '../../spec_helper'

describe "UncaughtThrowError" do
  it "is a subclass of ArgumentError" do
    ArgumentError.should be_ancestor_of(UncaughtThrowError)
  end
end

describe "UncaughtThrowError#tag" do
  it "returns the object thrown" do
    begin
      throw :abc

    rescue UncaughtThrowError => e
      e.tag.should == :abc
    end
  end
end
