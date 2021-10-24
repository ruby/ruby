require_relative '../../spec_helper'

describe "UncaughtThrowError#tag" do
  it "returns the object thrown" do
    begin
      throw :abc

    rescue UncaughtThrowError => e
      e.tag.should == :abc
    end
  end
end
