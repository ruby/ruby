# -*- encoding: binary -*-
require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "String#unpack" do
  it "ignores directives text from '#' to the first newline" do
    "\x01\x02\x03".unpack("c#this is a comment\nc").should == [1, 2]
  end

  it "ignores directives text from '#' to the end if no newline is present" do
    "\x01\x02\x03".unpack("c#this is a comment c").should == [1]
  end

  it "ignores comments at the start of the directives string" do
    "\x01\x02\x03".unpack("#this is a comment\nc").should == [1]
  end

  it "ignores the entire directive string if it is a comment" do
    "\x01\x02\x03".unpack("#this is a comment c").should == []
  end

  it "ignores multiple comments" do
    "\x01\x02\x03".unpack("c#comment\nc#comment\nc#c").should == [1, 2, 3]
  end
end
