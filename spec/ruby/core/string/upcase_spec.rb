# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#upcase" do
  it "returns a copy of self with all lowercase letters upcased" do
    "Hello".upcase.should == "HELLO"
    "hello".upcase.should == "HELLO"
  end

  ruby_version_is ''...'2.4' do
    it "is locale insensitive (only replaces a-z)" do
      "äöü".upcase.should == "äöü"

      str = Array.new(256) { |c| c.chr }.join
      expected = Array.new(256) do |i|
        c = i.chr
        c.between?("a", "z") ? c.upcase : c
      end.join

      str.upcase.should == expected
    end
  end

  ruby_version_is '2.4' do
    it "works for all of Unicode" do
      "äöü".upcase.should == "ÄÖÜ"
    end
  end

  it "taints result when self is tainted" do
    "".taint.upcase.tainted?.should == true
    "X".taint.upcase.tainted?.should == true
    "x".taint.upcase.tainted?.should == true
  end

  it "returns a subclass instance for subclasses" do
    StringSpecs::MyString.new("fooBAR").upcase.should be_an_instance_of(StringSpecs::MyString)
  end
end

describe "String#upcase!" do
  it "modifies self in place" do
    a = "HeLlO"
    a.upcase!.should equal(a)
    a.should == "HELLO"
  end


  ruby_version_is '2.4' do
    it "modifies self in place for all of Unicode" do
      a = "äöü"
      a.upcase!.should equal(a)
      a.should == "ÄÖÜ"
    end
  end

  it "returns nil if no modifications were made" do
    a = "HELLO"
    a.upcase!.should == nil
    a.should == "HELLO"
  end

  it "raises a #{frozen_error_class} when self is frozen" do
    lambda { "HeLlo".freeze.upcase! }.should raise_error(frozen_error_class)
    lambda { "HELLO".freeze.upcase! }.should raise_error(frozen_error_class)
  end
end
