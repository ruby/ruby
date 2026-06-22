require_relative '../../spec_helper'
require 'stringio'

describe "StringIO#each" do
  it "is an alias of StringIO#each_line" do
    StringIO.instance_method(:each).should == StringIO.instance_method(:each_line)
  end
end
