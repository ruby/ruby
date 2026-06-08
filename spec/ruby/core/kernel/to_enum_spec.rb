require_relative '../../spec_helper'

describe "Kernel#to_enum" do
  it "is defined in Kernel" do
    Kernel.method_defined?(:to_enum).should == true
  end

  it "returns a new enumerator" do
    "abc".to_enum.should.instance_of?(Enumerator)
  end

  it "defaults the first argument to :each" do
    enum = [1,2].to_enum
    enum.map { |v| v }.should == [1,2].each { |v| v }
  end

  it "sets regexp matches in the caller" do
    "wawa".to_enum(:scan, /./).map {|o| $& }.should == ["w", "a", "w", "a"]
    a = []
    "wawa".to_enum(:scan, /./).each {|o| a << $& }
    a.should == ["w", "a", "w", "a"]
  end

  it "exposes multi-arg yields as an array" do
    o = Object.new
    def o.each
      yield :a
      yield :b1, :b2
      yield [:c]
      yield :d1, :d2
      yield :e1, :e2, :e3
    end

    enum = o.to_enum
    enum.next.should == :a
    enum.next.should == [:b1, :b2]
    enum.next.should == [:c]
    enum.next.should == [:d1, :d2]
    enum.next.should == [:e1, :e2, :e3]
  end

  it "uses the passed block's value to calculate the size of the enumerator" do
    Object.new.to_enum { 100 }.size.should == 100
  end

  it "defers the evaluation of the passed block until #size is called" do
    ScratchPad.record []

    enum = Object.new.to_enum do
      ScratchPad << :called
      100
    end

    ScratchPad.recorded.should.empty?

    enum.size
    ScratchPad.recorded.should == [:called]
  end
end
