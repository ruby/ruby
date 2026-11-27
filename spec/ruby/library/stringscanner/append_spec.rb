require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#<<" do
  it "concatenates the given argument to self and returns self" do
    s = StringScanner.new(+"hello ")
    (s. << 'world').should == s
    s.string.should == "hello world"
    s.eos?.should == false
  end

  it "raises a TypeError if the given argument can't be converted to a String" do
    -> { StringScanner.new('hello') << :world    }.should.raise(TypeError)
    -> { StringScanner.new('hello') << mock('x') }.should.raise(TypeError)
  end
end

describe "StringScanner#<< when passed an Integer" do
  it "raises a TypeError" do
    a = StringScanner.new("hello world")
    -> { a << 333 }.should.raise(TypeError)
    b = StringScanner.new("")
    -> { b << (256 * 3 + 64) }.should.raise(TypeError)
    -> { b << -200           }.should.raise(TypeError)
  end

  it "doesn't call to_int on the argument" do
    x = mock('x')
    x.should_not_receive(:to_int)

    -> { StringScanner.new("") << x }.should.raise(TypeError)
  end
end
