require_relative '../../spec_helper'
require 'stringio'

describe "StringIO#isatty" do
  it "is an alias of StringIO#tty?" do
    StringIO.instance_method(:isatty).should == StringIO.instance_method(:tty?)
  end
end
