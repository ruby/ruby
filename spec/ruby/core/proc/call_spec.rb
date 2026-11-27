require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'fixtures/proc_call'
require_relative 'fixtures/proc_call_frozen'

describe "Proc#call" do
  it "invokes self" do
    Proc.new { "test!" }.call.should == "test!"
    -> { "test!" }.call.should == "test!"
    proc { "test!" }.call.should == "test!"
  end

  it "sets self's parameters to the given values" do
    Proc.new { |a, b| a + b }.call(1, 2).should == 3
    Proc.new { |*args| args }.call(1, 2, 3, 4).should == [1, 2, 3, 4]
    Proc.new { |_, *args| args }.call(1, 2, 3).should == [2, 3]

    -> a, b { a + b }.call(1, 2).should == 3
    -> *args { args }.call(1, 2, 3, 4).should == [1, 2, 3, 4]
    -> _, *args { args }.call(1, 2, 3).should == [2, 3]

    proc { |a, b| a + b }.call(1, 2).should == 3
    proc { |*args| args }.call(1, 2, 3, 4).should == [1, 2, 3, 4]
    proc { |_, *args| args }.call(1, 2, 3).should == [2, 3]
  end

  it "can receive block arguments" do
    Proc.new {|&b| b.call}.call {1 + 1}.should == 2
    -> &b { b.call}.call {1 + 1}.should == 2
    proc {|&b| b.call}.call {1 + 1}.should == 2
  end

  it "yields to the block given at declaration and not to the block argument" do
    proc_creator = Object.new
    def proc_creator.create
      Proc.new do |&b|
        yield
      end
    end
    a_proc = proc_creator.create { 7 }
    a_proc.call { 3 }.should == 7
  end

  it "can call its block argument declared with a block argument" do
    proc_creator = Object.new
    def proc_creator.create(method_name)
      Proc.new do |&b|
        yield + b.send(method_name)
      end
    end
    a_proc = proc_creator.create(:call) { 7 }
    a_proc.call { 3 }.should == 10
  end

  describe "on a Proc created with frozen_string_literal: true/false" do
    it "doesn't duplicate frozen strings" do
      ProcCallSpecs.call.frozen?.should == false
      ProcCallSpecs.call_freeze.frozen?.should == true
      ProcCallFrozenSpecs.call.frozen?.should == true
      ProcCallFrozenSpecs.call_freeze.frozen?.should == true
    end
  end

  context "on a Proc created with Proc.new" do
    it "replaces missing arguments with nil" do
      Proc.new { |a, b| [a, b] }.call.should == [nil, nil]
      Proc.new { |a, b| [a, b] }.call(1).should == [1, nil]
    end

    it "silently ignores extra arguments" do
      Proc.new { |a, b| a + b }.call(1, 2, 5).should == 3
    end

    it "auto-explodes a single Array argument" do
      p = Proc.new { |a, b| [a, b] }
      p.call(1, 2).should == [1, 2]
      p.call([1, 2]).should == [1, 2]
      p.call([1, 2, 3]).should == [1, 2]
      p.call([1, 2, 3], 4).should == [[1, 2, 3], 4]
    end
  end

  context "on a Proc created with Kernel#lambda or Kernel#proc" do
    it "ignores excess arguments when self is a proc" do
      a = proc {|x| x}.call(1, 2)
      a.should == 1

      a = proc {|x| x}.call(1, 2, 3)
      a.should == 1

      a = proc {|x:| x}.call(2, x: 1)
      a.should == 1
    end

    it "will call #to_ary on argument and return self if return is nil" do
      argument = ProcSpecs::ToAryAsNil.new
      result = proc { |x, _| x }.call(argument)
      result.should == argument
    end

    it "substitutes nil for missing arguments when self is a proc" do
      proc {|x,y| [x,y]}.call.should == [nil,nil]

      a = proc {|x,y| [x, y]}.call(1)
      a.should == [1,nil]
    end

    it "raises an ArgumentError on excess arguments when self is a lambda" do
      -> {
        -> x { x }.call(1, 2)
      }.should.raise(ArgumentError)

      -> {
        -> x { x }.call(1, 2, 3)
      }.should.raise(ArgumentError)
    end

    it "raises an ArgumentError on missing arguments when self is a lambda" do
      -> {
        -> x { x }.call
      }.should.raise(ArgumentError)

      -> {
        -> x, y { [x,y] }.call(1)
      }.should.raise(ArgumentError)
    end

    it "treats a single Array argument as a single argument when self is a lambda" do
      -> a { a }.call([1, 2]).should == [1, 2]
      -> a, b { [a, b] }.call([1, 2], 3).should == [[1,2], 3]
    end

    it "treats a single Array argument as a single argument when self is a proc" do
      proc { |a| a }.call([1, 2]).should == [1, 2]
      proc { |a, b| [a, b] }.call([1, 2], 3).should == [[1,2], 3]
    end
  end
end
