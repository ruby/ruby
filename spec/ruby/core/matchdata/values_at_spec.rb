require_relative '../../spec_helper'

describe "MatchData#values_at" do
  # Should be synchronized with core/array/values_at_spec.rb and core/struct/values_at_spec.rb
  #
  # /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").to_a # => ["HX1138", "H", "X", "113", "8"]

  context "when passed a list of Integers" do
    it "returns an array containing each value given by one of integers" do
      /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(0, 2, -2).should == ["HX1138", "X", "113"]
    end

    it "returns nil value for any integer that is out of range" do
      /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(5).should == [nil]
      /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(-6).should == [nil]
    end
  end

  context "when passed an integer Range" do
    it "returns an array containing each value given by the elements of the range" do
      /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(0..2).should == ["HX1138", "H", "X"]
    end

    it "fills with nil values for range elements larger than the captured values number" do
      /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(0..5).should == ["HX1138", "H", "X", "113", "8", nil]
    end

    it "raises RangeError if any element of the range is negative and out of range" do
      -> { /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(-6..3) }.should raise_error(RangeError, "-6..3 out of range")
    end

    it "supports endless Range" do
      /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(0..).should == ["HX1138", "H", "X", "113", "8"]
    end

    it "supports beginningless Range" do
      /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(..2).should == ["HX1138", "H", "X"]
    end

    it "returns an empty Array when Range is empty" do
      /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(2..0).should == []
    end
  end

  context "when passed names" do
    it 'slices captures with the given names' do
      /(?<a>.)(?<b>.)(?<c>.)/.match('012').values_at(:c, :a).should == ['2', '0']
    end

    it 'slices captures with the given String names' do
      /(?<a>.)(?<b>.)(?<c>.)/.match('012').values_at('c', 'a').should == ['2', '0']
    end
  end

  it "supports multiple integer Ranges" do
    /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(1..2, 2..3).should == ["H", "X", "X", "113"]
  end

  it "supports mixing integer Ranges and Integers" do
    /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(1..2, 4).should == ["H", "X", "8"]
  end

  it 'supports mixing of names and indices' do
    /\A(?<a>.)(?<b>.)\z/.match('01').values_at(0, 1, 2, :a, :b).should == ['01', '0', '1', '0', '1']
  end

  it "returns a new empty Array if no arguments given" do
    /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at().should == []
  end

  it "fails when passed arguments of unsupported types" do
    -> {
      /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(Object.new)
    }.should raise_error(TypeError, "no implicit conversion of Object into Integer")
  end
end
