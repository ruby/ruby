require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Data#deconstruct" do
  it "returns a hash of attributes" do
    klass = Data.define(:x, :y)
    d = klass.new(1, 2)
    d.deconstruct_keys([:x, :y]).should == {x: 1, y: 2}
  end

  it "requires one argument" do
    klass = Data.define(:x, :y)
    d = klass.new(1, 2)

    -> {
      d.deconstruct_keys
    }.should raise_error(ArgumentError, /wrong number of arguments \(given 0, expected 1\)/)
  end

  it "returns only specified keys" do
    klass = Data.define(:x, :y)
    d = klass.new(1, 2)

    d.deconstruct_keys([:x, :y]).should == {x: 1, y: 2}
    d.deconstruct_keys([:x]    ).should == {x: 1}
    d.deconstruct_keys([]      ).should == {}
  end

  it "accepts string attribute names" do
    klass = Data.define(:x, :y)
    d = klass.new(1, 2)
    d.deconstruct_keys(['x', 'y']).should == {'x' => 1, 'y' => 2}
  end

  it "accepts argument position number as well but returns them as keys" do
    klass = Data.define(:x, :y)
    d = klass.new(1, 2)

    d.deconstruct_keys([0, 1]).should == {0 => 1, 1 => 2}
    d.deconstruct_keys([0]   ).should == {0 => 1}
    d.deconstruct_keys([-1]  ).should == {-1 => 2}
  end

  it "ignores incorrect position numbers" do
    klass = Data.define(:x, :y)
    d = klass.new(1, 2)

    d.deconstruct_keys([0, 3]).should == {0 => 1}
  end

  it "support mixing attribute names and argument position numbers" do
    klass = Data.define(:x, :y)
    d = klass.new(1, 2)

    d.deconstruct_keys([0, :x]).should == {0 => 1, :x => 1}
  end

  it "returns an empty hash when there are more keys than attributes" do
    klass = Data.define(:x, :y)
    d = klass.new(1, 2)
    d.deconstruct_keys([:x, :y, :x]).should == {}
  end

  it "returns at first not existing attribute name" do
    klass = Data.define(:x, :y)
    d = klass.new(1, 2)

    d.deconstruct_keys([:a, :x]).should == {}
    d.deconstruct_keys([:x, :a]).should == {x: 1}
  end

  it "returns at first not existing argument position number" do
    klass = Data.define(:x, :y)
    d = klass.new(1, 2)

    d.deconstruct_keys([3, 0]).should == {}
    d.deconstruct_keys([0, 3]).should == {0 => 1}
  end

  it "accepts nil argument and return all the attributes" do
    klass = Data.define(:x, :y)
    d = klass.new(1, 2)

    d.deconstruct_keys(nil).should == {x: 1, y: 2}
  end

  it "raises TypeError if index is not a String, a Symbol and not convertible to Integer " do
    klass = Data.define(:x, :y)
    d = klass.new(1, 2)

    -> {
      d.deconstruct_keys([0, []])
    }.should raise_error(TypeError, "no implicit conversion of Array into Integer")
  end

  it "raise TypeError if passed anything except nil or array" do
    klass = Data.define(:x, :y)
    d = klass.new(1, 2)

    -> { d.deconstruct_keys('x') }.should raise_error(TypeError, /expected Array or nil/)
    -> { d.deconstruct_keys(1)   }.should raise_error(TypeError, /expected Array or nil/)
    -> { d.deconstruct_keys(:x)  }.should raise_error(TypeError, /expected Array or nil/)
    -> { d.deconstruct_keys({})  }.should raise_error(TypeError, /expected Array or nil/)
  end
end
