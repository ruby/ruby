require_relative '../../spec_helper'
require 'stringio'

describe "StringIO#tty?" do
  it "returns false" do
    StringIO.new("tty").tty?.should == false
  end
end
