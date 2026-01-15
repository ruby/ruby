require_relative '../../spec_helper'

describe "MatchData#byteoffset" do
  it "returns beginning and ending byte-based offset of whole matched substring for 0 element" do
    m = /(.)(.)(\d+)(\d)/.match("THX1138.")
    m.byteoffset(0).should == [1, 7]
  end

  it "returns beginning and ending byte-based offset of n-th match, all the subsequent elements are capturing groups" do
    m = /(.)(.)(\d+)(\d)/.match("THX1138.")

    m.byteoffset(2).should == [2, 3]
    m.byteoffset(3).should == [3, 6]
    m.byteoffset(4).should == [6, 7]
  end

  it "accepts String as a reference to a named capture" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    m.byteoffset("f").should == [0, 3]
    m.byteoffset("b").should == [3, 6]
  end

  it "accepts Symbol as a reference to a named capture" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    m.byteoffset(:f).should == [0, 3]
    m.byteoffset(:b).should == [3, 6]
  end

  it "returns [nil, nil] if a capturing group is optional and doesn't match" do
    m = /(?<x>q..)?/.match("foobarbaz")

    m.byteoffset("x").should == [nil, nil]
    m.byteoffset(1).should == [nil, nil]
  end

  it "returns correct beginning and ending byte-based offset for multi-byte strings" do
    m = /\A\u3042(.)(.)?(.)\z/.match("\u3042\u3043\u3044")

    m.byteoffset(1).should == [3, 6]
    m.byteoffset(3).should == [6, 9]
  end

  it "returns [nil, nil] if a capturing group is optional and doesn't match for multi-byte string" do
    m = /\A\u3042(.)(.)?(.)\z/.match("\u3042\u3043\u3044")

    m.byteoffset(2).should == [nil, nil]
  end

  it "converts argument into integer if is not String nor Symbol" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    obj = Object.new
    def obj.to_int; 2; end

    m.byteoffset(1r).should == [0, 3]
    m.byteoffset(1.1).should == [0, 3]
    m.byteoffset(obj).should == [3, 6]
  end

  it "raises IndexError if there is no group with the provided name" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    -> {
      m.byteoffset("y")
    }.should raise_error(IndexError, "undefined group name reference: y")

    -> {
      m.byteoffset(:y)
    }.should raise_error(IndexError, "undefined group name reference: y")
  end

  it "raises IndexError if index is out of bounds" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    -> {
      m.byteoffset(-1)
    }.should raise_error(IndexError, "index -1 out of matches")

    -> {
      m.byteoffset(3)
    }.should raise_error(IndexError, "index 3 out of matches")
  end

  it "raises TypeError if can't convert argument into Integer" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    -> {
      m.byteoffset([])
    }.should raise_error(TypeError, "no implicit conversion of Array into Integer")
  end
end
