require_relative '../../spec_helper'
require 'stringio'

describe "StringIO#fileno" do
  it "returns nil" do
    StringIO.new("nuffin").fileno.should == nil
  end
end
