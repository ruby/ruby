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
      o.should.tainted?
    end

    it "raises FrozenError on an untainted, frozen object" do
      o = Object.new.freeze
      -> { o.taint }.should raise_error(FrozenError)
    end

    it "does not raise an error on a tainted, frozen object" do
      o = Object.new.taint.freeze
      o.taint.should equal(o)
    end

    it "has no effect on immediate values" do
      [nil, true, false].each do |v|
        v.taint
        v.should_not.tainted?
      end
    end

    it "no raises a RuntimeError on symbols" do
      v = :sym
      -> { v.taint }.should_not raise_error(RuntimeError)
      v.should_not.tainted?
    end

    it "no raises error on integer values" do
      [1].each do |v|
        -> { v.taint }.should_not raise_error(RuntimeError)
        v.should_not.tainted?
      end
    end
  end

  ruby_version_is "2.7"..."3.0" do
    it "is a no-op" do
      o = Object.new
      o.taint
      o.should_not.tainted?
    end

    it "warns in verbose mode" do
      -> {
        obj = mock("tainted")
        obj.taint
      }.should complain(/Object#taint is deprecated and will be removed in Ruby 3.2/, verbose: true)
    end
  end
end
