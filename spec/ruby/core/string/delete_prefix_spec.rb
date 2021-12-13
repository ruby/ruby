# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#delete_prefix" do
  it "returns a copy of the string, with the given prefix removed" do
    'hello'.delete_prefix('hell').should == 'o'
    'hello'.delete_prefix('hello').should == ''
  end

  it "returns a copy of the string, when the prefix isn't found" do
    s = 'hello'
    r = s.delete_prefix('hello!')
    r.should_not equal s
    r.should == s
    r = s.delete_prefix('ell')
    r.should_not equal s
    r.should == s
    r = s.delete_prefix('')
    r.should_not equal s
    r.should == s
  end

  ruby_version_is ''...'2.7' do
    it "taints resulting strings when other is tainted" do
      'hello'.taint.delete_prefix('hell').should.tainted?
      'hello'.taint.delete_prefix('').should.tainted?
    end
  end

  it "doesn't set $~" do
    $~ = nil

    'hello'.delete_prefix('hell')
    $~.should == nil
  end

  it "calls to_str on its argument" do
    o = mock('x')
    o.should_receive(:to_str).and_return 'hell'
    'hello'.delete_prefix(o).should == 'o'
  end

  ruby_version_is ''...'3.0' do
    it "returns a subclass instance when called on a subclass instance" do
      s = StringSpecs::MyString.new('hello')
      s.delete_prefix('hell').should be_an_instance_of(StringSpecs::MyString)
    end
  end

  ruby_version_is '3.0' do
    it "returns a String instance when called on a subclass instance" do
      s = StringSpecs::MyString.new('hello')
      s.delete_prefix('hell').should be_an_instance_of(String)
    end
  end
end

describe "String#delete_prefix!" do
  it "removes the found prefix" do
    s = 'hello'
    s.delete_prefix!('hell').should equal(s)
    s.should == 'o'
  end

  it "returns nil if no change is made" do
    s = 'hello'
    s.delete_prefix!('ell').should == nil
    s.delete_prefix!('').should == nil
  end

  it "doesn't set $~" do
    $~ = nil

    'hello'.delete_prefix!('hell')
    $~.should == nil
  end

  it "calls to_str on its argument" do
    o = mock('x')
    o.should_receive(:to_str).and_return 'hell'
    'hello'.delete_prefix!(o).should == 'o'
  end

  it "raises a FrozenError when self is frozen" do
    -> { 'hello'.freeze.delete_prefix!('hell') }.should raise_error(FrozenError)
    -> { 'hello'.freeze.delete_prefix!('') }.should raise_error(FrozenError)
    -> { ''.freeze.delete_prefix!('') }.should raise_error(FrozenError)
  end
end
