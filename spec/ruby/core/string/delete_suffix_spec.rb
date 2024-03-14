# -*- encoding: utf-8 -*-
# frozen_string_literal: false
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#delete_suffix" do
  it "returns a copy of the string, with the given suffix removed" do
    'hello'.delete_suffix('ello').should == 'h'
    'hello'.delete_suffix('hello').should == ''
  end

  it "returns a copy of the string, when the suffix isn't found" do
    s = 'hello'
    r = s.delete_suffix('!hello')
    r.should_not equal s
    r.should == s
    r = s.delete_suffix('ell')
    r.should_not equal s
    r.should == s
    r = s.delete_suffix('')
    r.should_not equal s
    r.should == s
  end

  it "does not remove partial bytes, only full characters" do
    "\xe3\x81\x82".delete_suffix("\x82").should == "\xe3\x81\x82"
  end

  it "doesn't set $~" do
    $~ = nil

    'hello'.delete_suffix('ello')
    $~.should == nil
  end

  it "calls to_str on its argument" do
    o = mock('x')
    o.should_receive(:to_str).and_return 'ello'
    'hello'.delete_suffix(o).should == 'h'
  end

  it "returns a String instance when called on a subclass instance" do
    s = StringSpecs::MyString.new('hello')
    s.delete_suffix('ello').should be_an_instance_of(String)
  end

  it "returns a String in the same encoding as self" do
    "hello".encode("US-ASCII").delete_suffix("ello").encoding.should == Encoding::US_ASCII
  end
end

describe "String#delete_suffix!" do
  it "removes the found prefix" do
    s = 'hello'
    s.delete_suffix!('ello').should equal(s)
    s.should == 'h'
  end

  it "returns nil if no change is made" do
    s = 'hello'
    s.delete_suffix!('ell').should == nil
    s.delete_suffix!('').should == nil
  end

  it "doesn't set $~" do
    $~ = nil

    'hello'.delete_suffix!('ello')
    $~.should == nil
  end

  it "calls to_str on its argument" do
    o = mock('x')
    o.should_receive(:to_str).and_return 'ello'
    'hello'.delete_suffix!(o).should == 'h'
  end

  it "raises a FrozenError when self is frozen" do
    -> { 'hello'.freeze.delete_suffix!('ello') }.should raise_error(FrozenError)
    -> { 'hello'.freeze.delete_suffix!('') }.should raise_error(FrozenError)
    -> { ''.freeze.delete_suffix!('') }.should raise_error(FrozenError)
  end
end
