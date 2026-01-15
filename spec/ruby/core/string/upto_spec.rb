require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#upto" do
  it "passes successive values, starting at self and ending at other_string, to the block" do
    a = []
    "*+".upto("*3") { |s| a << s }
    a.should == ["*+", "*,", "*-", "*.", "*/", "*0", "*1", "*2", "*3"]
  end

  it "calls the block once even when start equals stop" do
    a = []
    "abc".upto("abc") { |s| a << s }
    a.should == ["abc"]
  end

  it "doesn't call block with self even if self is less than stop but stop length is less than self length" do
    a = []
    "25".upto("5") { |s| a << s }
    a.should == []
  end

  it "doesn't call block if stop is less than self and stop length is less than self length" do
    a = []
    "25".upto("1") { |s| a << s }
    a.should == []
  end

  it "doesn't call the block if self is greater than stop" do
    a = []
    "5".upto("2") { |s| a << s }
    a.should == []
  end

  it "stops iterating as soon as the current value's character count gets higher than stop's" do
    a = []
    "96".upto("AA") { |s| a << s }
    a.should == ["96", "97", "98", "99"]
  end

  it "returns self" do
    "abc".upto("abd") { }.should == "abc"
    "5".upto("2") { |i| i }.should == "5"
  end

  it "tries to convert other to string using to_str" do
    other = mock('abd')
    def other.to_str() "abd" end

    a = []
    "abc".upto(other) { |s| a << s }
    a.should == ["abc", "abd"]
  end

  it "raises a TypeError if other can't be converted to a string" do
    -> { "abc".upto(123) { }      }.should raise_error(TypeError)
    -> { "abc".upto(mock('x')){ } }.should raise_error(TypeError)
  end


  it "does not work with symbols" do
    -> { "a".upto(:c).to_a }.should raise_error(TypeError)
  end

  it "returns non-alphabetic characters in the ASCII range for single letters" do
    "9".upto("A").to_a.should == ["9", ":", ";", "<", "=", ">", "?", "@", "A"]
    "Z".upto("a").to_a.should == ["Z", "[", "\\", "]", "^", "_", "`", "a"]
    "z".upto("~").to_a.should == ["z", "{", "|", "}", "~"]
  end

  it "stops before the last value if exclusive" do
    a = []
    "a".upto("d", true) { |s| a << s}
    a.should == ["a", "b", "c"]
  end

  it "works with non-ASCII ranges" do
    a = []
    'Σ'.upto('Ω') { |s| a << s }
    a.should == ["Σ", "Τ", "Υ", "Φ", "Χ", "Ψ", "Ω"]
  end

  it "raises Encoding::CompatibilityError when incompatible characters are given" do
    char1 = 'a'.dup.force_encoding("EUC-JP")
    char2 = 'b'.dup.force_encoding("ISO-2022-JP")
    -> { char1.upto(char2) {} }.should raise_error(Encoding::CompatibilityError, "incompatible character encodings: EUC-JP and ISO-2022-JP")
  end

  describe "on sequence of numbers" do
    it "calls the block as Integer#upto"  do
      "8".upto("11").to_a.should == 8.upto(11).map(&:to_s)
    end
  end

  describe "when no block is given" do
    it "returns an enumerator" do
      enum = "aaa".upto("baa", true)
      enum.should be_an_instance_of(Enumerator)
      enum.count.should == 26**2
    end

    describe "returned Enumerator" do
      describe "size" do
        it "should return nil" do
          "a".upto("b").size.should == nil
        end
      end
    end
  end
end
