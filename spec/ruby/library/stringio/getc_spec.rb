require_relative '../../spec_helper'
require 'stringio'
require_relative 'shared/getc'

describe "StringIO#getc" do
  it_behaves_like :stringio_getc, :getc

  it "returns the character at the current position" do
    io = StringIO.new("example")

    io.getc.should == ?e
    io.getc.should == ?x
    io.getc.should == ?a
  end
end

describe "StringIO#getc when self is not readable" do
  it_behaves_like :stringio_getc_not_readable, :getc
end
