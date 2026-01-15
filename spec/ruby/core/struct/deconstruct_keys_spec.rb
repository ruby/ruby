require_relative '../../spec_helper'

describe "Struct#deconstruct_keys" do
  it "returns a hash of attributes" do
    struct = Struct.new(:x, :y)
    s = struct.new(1, 2)

    s.deconstruct_keys([:x, :y]).should == {x: 1, y: 2}
  end

  it "requires one argument" do
    struct = Struct.new(:x)
    obj = struct.new(1)

    -> {
      obj.deconstruct_keys
    }.should raise_error(ArgumentError, /wrong number of arguments \(given 0, expected 1\)/)
  end

  it "returns only specified keys" do
    struct = Struct.new(:x, :y, :z)
    s = struct.new(1, 2, 3)

    s.deconstruct_keys([:x, :y]).should == {x: 1, y: 2}
    s.deconstruct_keys([:x]    ).should == {x: 1}
    s.deconstruct_keys([]      ).should == {}
  end

  it "accepts string attribute names" do
    struct = Struct.new(:x, :y)
    s = struct.new(1, 2)

    s.deconstruct_keys(['x', 'y']).should == {'x' => 1, 'y' => 2}
  end

  it "accepts argument position number as well but returns them as keys" do
    struct = Struct.new(:x, :y, :z)
    s = struct.new(10, 20, 30)

    s.deconstruct_keys([0, 1, 2]).should == {0 => 10, 1 => 20, 2 => 30}
    s.deconstruct_keys([0, 1]   ).should == {0 => 10, 1 => 20}
    s.deconstruct_keys([0]      ).should == {0 => 10}
    s.deconstruct_keys([-1]     ).should == {-1 => 30}
  end

  it "ignores incorrect position numbers" do
    struct = Struct.new(:x, :y, :z)
    s = struct.new(10, 20, 30)

    s.deconstruct_keys([0, 3]).should == {0 => 10}
  end

  it "support mixing attribute names and argument position numbers" do
    struct = Struct.new(:x, :y)
    s = struct.new(1, 2)

    s.deconstruct_keys([0, :x]).should == {0 => 1, :x => 1}
  end

  it "returns an empty hash when there are more keys than attributes" do
    struct = Struct.new(:x, :y)
    s = struct.new(1, 2)

    s.deconstruct_keys([:x, :y, :a]).should == {}
  end

  it "returns at first not existing attribute name" do
    struct = Struct.new(:x, :y)
    s = struct.new(1, 2)

    s.deconstruct_keys([:a, :x]).should == {}
    s.deconstruct_keys([:x, :a]).should == {x: 1}
  end

  it "returns at first not existing argument position number" do
    struct = Struct.new(:x, :y)
    s = struct.new(1, 2)

    s.deconstruct_keys([3, 0]).should == {}
    s.deconstruct_keys([0, 3]).should == {0 => 1}
  end

  it "accepts nil argument and return all the attributes" do
    struct = Struct.new(:x, :y)
    obj = struct.new(1, 2)

    obj.deconstruct_keys(nil).should == {x: 1, y: 2}
  end

  it "tries to convert a key with #to_int if index is not a String nor a Symbol, but responds to #to_int" do
    struct = Struct.new(:x, :y)
    s = struct.new(1, 2)

    key = mock("to_int")
    key.should_receive(:to_int).and_return(1)

    s.deconstruct_keys([key]).should == { key => 2 }
  end

  it "raises a TypeError if the conversion with #to_int does not return an Integer" do
    struct = Struct.new(:x, :y)
    s = struct.new(1, 2)

    key = mock("to_int")
    key.should_receive(:to_int).and_return("not an Integer")

    -> {
      s.deconstruct_keys([key])
    }.should raise_error(TypeError, /can't convert MockObject to Integer/)
  end

  it "raises TypeError if index is not a String, a Symbol and not convertible to Integer" do
    struct = Struct.new(:x, :y)
    s = struct.new(1, 2)

    -> {
      s.deconstruct_keys([0, []])
    }.should raise_error(TypeError, "no implicit conversion of Array into Integer")
  end

  it "raise TypeError if passed anything except nil or array" do
    struct = Struct.new(:x, :y)
    s = struct.new(1, 2)

    -> { s.deconstruct_keys('x') }.should raise_error(TypeError, /expected Array or nil/)
    -> { s.deconstruct_keys(1)   }.should raise_error(TypeError, /expected Array or nil/)
    -> { s.deconstruct_keys(:x)  }.should raise_error(TypeError, /expected Array or nil/)
    -> { s.deconstruct_keys({})  }.should raise_error(TypeError, /expected Array or nil/)
  end
end
