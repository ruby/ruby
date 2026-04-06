require_relative '../../spec_helper'

describe "MatchData#deconstruct_keys" do
  it "returns whole hash for nil as an argument" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    m.deconstruct_keys(nil).should == { f: "foo", b: "bar" }
  end

  it "returns only specified keys" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    m.deconstruct_keys([:f]).should == { f: "foo" }
  end

  it "requires one argument" do
    m = /l/.match("l")

    -> {
      m.deconstruct_keys
    }.should raise_error(ArgumentError, "wrong number of arguments (given 0, expected 1)")
  end

  it "it raises error when argument is neither nil nor array" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    -> { m.deconstruct_keys(1) }.should raise_error(TypeError, "wrong argument type Integer (expected Array)")
    -> { m.deconstruct_keys("asd") }.should raise_error(TypeError, "wrong argument type String (expected Array)")
    -> { m.deconstruct_keys(:x) }.should raise_error(TypeError, "wrong argument type Symbol (expected Array)")
    -> { m.deconstruct_keys({}) }.should raise_error(TypeError, "wrong argument type Hash (expected Array)")
  end

  it "returns {} when passed []" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    m.deconstruct_keys([]).should == {}
  end

  it "does not accept non-Symbol keys" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    -> {
      m.deconstruct_keys(['year', :foo])
    }.should raise_error(TypeError, "wrong argument type String (expected Symbol)")
  end

  it "process keys till the first non-existing one" do
    m = /(?<f>foo)(?<b>bar)(?<c>baz)/.match("foobarbaz")

    m.deconstruct_keys([:f, :a, :b]).should == { f: "foo" }
  end

  it "returns {} when there are no named captured groups at all" do
    m = /foo.+/.match("foobar")

    m.deconstruct_keys(nil).should == {}
  end

  it "returns {} when passed more keys than named captured groups" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")
    m.deconstruct_keys([:f, :b, :c]).should == {}
  end

  it "includes non-participating captures as nil for nil argument" do
    m = "hello".match(/(?<a>hello)(?<b>world)?/)
    m.deconstruct_keys(nil).should == { a: "hello", b: nil }
  end

  it "includes non-participating captures as nil for explicit keys" do
    m = "hello".match(/(?<a>hello)(?<b>world)?/)
    m.deconstruct_keys([:a, :b]).should == { a: "hello", b: nil }
  end

  it "does not stop iterating at a non-participating capture" do
    m = "hello!".match(/(?<a>hello)(?<b>world)?(?<c>!)/)
    m.deconstruct_keys([:b, :c, :a]).should == { b: nil, c: "!", a: "hello" }
  end
end
