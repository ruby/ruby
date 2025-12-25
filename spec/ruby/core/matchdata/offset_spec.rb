require_relative '../../spec_helper'

describe "MatchData#offset" do
  it "returns beginning and ending character offset of whole matched substring for 0 element" do
    m = /(.)(.)(\d+)(\d)/.match("THX1138.")
    m.offset(0).should == [1, 7]
  end

  it "returns beginning and ending character offset of n-th match, all the subsequent elements are capturing groups" do
    m = /(.)(.)(\d+)(\d)/.match("THX1138.")

    m.offset(2).should == [2, 3]
    m.offset(3).should == [3, 6]
    m.offset(4).should == [6, 7]
  end

  it "accepts String as a reference to a named capture" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    m.offset("f").should == [0, 3]
    m.offset("b").should == [3, 6]
  end

  it "accepts Symbol as a reference to a named capture" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    m.offset(:f).should == [0, 3]
    m.offset(:b).should == [3, 6]
  end

  it "returns [nil, nil] if a capturing group is optional and doesn't match" do
    m = /(?<x>q..)?/.match("foobarbaz")

    m.offset("x").should == [nil, nil]
    m.offset(1).should == [nil, nil]
  end

  it "returns correct beginning and ending character offset for multi-byte strings" do
    m = /\A\u3042(.)(.)?(.)\z/.match("\u3042\u3043\u3044")

    m.offset(1).should == [1, 2]
    m.offset(3).should == [2, 3]
  end

  not_supported_on :opal do
    it "returns correct character offset for multi-byte strings with unicode regexp" do
      m = /\A\u3042(.)(.)?(.)\z/u.match("\u3042\u3043\u3044")

      m.offset(1).should == [1, 2]
      m.offset(3).should == [2, 3]
    end
  end

  it "returns [nil, nil] if a capturing group is optional and doesn't match for multi-byte string" do
    m = /\A\u3042(.)(.)?(.)\z/.match("\u3042\u3043\u3044")

    m.offset(2).should == [nil, nil]
  end

  it "converts argument into integer if is not String nor Symbol" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    obj = Object.new
    def obj.to_int; 2; end

    m.offset(1r).should == [0, 3]
    m.offset(1.1).should == [0, 3]
    m.offset(obj).should == [3, 6]
  end

  it "raises IndexError if there is no group with the provided name" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    -> {
      m.offset("y")
    }.should raise_error(IndexError, "undefined group name reference: y")

    -> {
      m.offset(:y)
    }.should raise_error(IndexError, "undefined group name reference: y")
  end

  it "raises IndexError if index is out of bounds" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    -> {
      m.offset(-1)
    }.should raise_error(IndexError, "index -1 out of matches")

    -> {
      m.offset(3)
    }.should raise_error(IndexError, "index 3 out of matches")
  end

  it "raises TypeError if can't convert argument into Integer" do
    m = /(?<f>foo)(?<b>bar)/.match("foobar")

    -> {
      m.offset([])
    }.should raise_error(TypeError, "no implicit conversion of Array into Integer")
  end
end
