require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#taint" do
  ruby_version_is ''...'2.7' do
    it "returns self" do
      o = Object.new
      o.taint.should equal(o)
    end

    it "sets the tainted bit" do
      o = Object.new
      o.taint
      o.tainted?.should == true
    end

    it "raises #{frozen_error_class} on an untainted, frozen object" do
      o = Object.new.freeze
      -> { o.taint }.should raise_error(frozen_error_class)
    end

    it "does not raise an error on a tainted, frozen object" do
      o = Object.new.taint.freeze
      o.taint.should equal(o)
    end

    it "has no effect on immediate values" do
      [nil, true, false].each do |v|
        v.taint
        v.tainted?.should == false
      end
    end

    it "no raises a RuntimeError on symbols" do
      v = :sym
      -> { v.taint }.should_not raise_error(RuntimeError)
      v.tainted?.should == false
    end

    it "no raises error on fixnum values" do
      [1].each do |v|
        -> { v.taint }.should_not raise_error(RuntimeError)
        v.tainted?.should == false
      end
    end
  end
end
