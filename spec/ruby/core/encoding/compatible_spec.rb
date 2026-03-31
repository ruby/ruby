# encoding: binary

require_relative '../../spec_helper'

# TODO: add IO

describe "Encoding.compatible? String, String" do
  describe "when the first's Encoding is valid US-ASCII" do
    before :each do
      @str = "abc".dup.force_encoding Encoding::US_ASCII
    end

    it "returns US-ASCII when the second's is US-ASCII" do
      Encoding.compatible?(@str, "def".encode("us-ascii")).should == Encoding::US_ASCII
    end

    it "returns US-ASCII if the second String is BINARY and ASCII only" do
      Encoding.compatible?(@str, "\x7f").should == Encoding::US_ASCII
    end

    it "returns BINARY if the second String is BINARY but not ASCII only" do
      Encoding.compatible?(@str, "\xff").should == Encoding::BINARY
    end

    it "returns US-ASCII if the second String is UTF-8 and ASCII only" do
      Encoding.compatible?(@str, "\x7f".encode("utf-8")).should == Encoding::US_ASCII
    end

    it "returns UTF-8 if the second String is UTF-8 but not ASCII only" do
      Encoding.compatible?(@str, "\u3042".encode("utf-8")).should == Encoding::UTF_8
    end
  end

  describe "when the first's Encoding is ASCII compatible and ASCII only" do
    it "returns the first's Encoding if the second is ASCII compatible and ASCII only" do
      [ [Encoding, "abc".dup.force_encoding("UTF-8"), "123".dup.force_encoding("Shift_JIS"), Encoding::UTF_8],
        [Encoding, "123".dup.force_encoding("Shift_JIS"), "abc".dup.force_encoding("UTF-8"), Encoding::Shift_JIS]
      ].should be_computed_by(:compatible?)
    end

    it "returns the first's Encoding if the second is ASCII compatible and ASCII only" do
      [ [Encoding, "abc".dup.force_encoding("BINARY"), "123".dup.force_encoding("US-ASCII"), Encoding::BINARY],
        [Encoding, "123".dup.force_encoding("US-ASCII"), "abc".dup.force_encoding("BINARY"), Encoding::US_ASCII]
      ].should be_computed_by(:compatible?)
    end

    it "returns the second's Encoding if the second is ASCII compatible but not ASCII only" do
      [ [Encoding, "abc".dup.force_encoding("UTF-8"), "\xff".dup.force_encoding("Shift_JIS"), Encoding::Shift_JIS],
        [Encoding, "123".dup.force_encoding("Shift_JIS"), "\xff".dup.force_encoding("UTF-8"), Encoding::UTF_8],
        [Encoding, "abc".dup.force_encoding("BINARY"), "\xff".dup.force_encoding("US-ASCII"), Encoding::US_ASCII],
        [Encoding, "123".dup.force_encoding("US-ASCII"), "\xff".dup.force_encoding("BINARY"), Encoding::BINARY],
      ].should be_computed_by(:compatible?)
    end

    it "returns nil if the second's Encoding is not ASCII compatible" do
      a = "abc".dup.force_encoding("UTF-8")
      b = "1234".dup.force_encoding("UTF-16LE")
      Encoding.compatible?(a, b).should be_nil
    end
  end

  describe "when the first's Encoding is ASCII compatible but not ASCII only" do
    it "returns the first's Encoding if the second's is valid US-ASCII" do
      Encoding.compatible?("\xff", "def".encode("us-ascii")).should == Encoding::BINARY
    end

    it "returns the first's Encoding if the second's is UTF-8 and ASCII only" do
      Encoding.compatible?("\xff", "\u{7f}".encode("utf-8")).should == Encoding::BINARY
    end

    it "returns nil if the second encoding is ASCII compatible but neither String's encoding is ASCII only" do
      Encoding.compatible?("\xff", "\u3042".encode("utf-8")).should be_nil
    end
  end

  describe "when the first's Encoding is not ASCII compatible" do
    before :each do
      @str = "abc".dup.force_encoding Encoding::UTF_7
    end

    it "returns nil when the second String is US-ASCII" do
      Encoding.compatible?(@str, "def".encode("us-ascii")).should be_nil
    end

    it "returns nil when the second String is BINARY and ASCII only" do
      Encoding.compatible?(@str, "\x7f").should be_nil
    end

    it "returns nil when the second String is BINARY but not ASCII only" do
      Encoding.compatible?(@str, "\xff").should be_nil
    end

    it "returns the Encoding when the second's Encoding is not ASCII compatible but the same as the first's Encoding" do
      encoding = Encoding.compatible?(@str, "def".dup.force_encoding("utf-7"))
      encoding.should == Encoding::UTF_7
    end
  end

  describe "when the first's Encoding is invalid" do
    before :each do
      @str = "\xff".dup.force_encoding Encoding::UTF_8
    end

    it "returns the first's Encoding when the second's Encoding is US-ASCII" do
      Encoding.compatible?(@str, "def".encode("us-ascii")).should == Encoding::UTF_8
    end

    it "returns the first's Encoding when the second String is ASCII only" do
      Encoding.compatible?(@str, "\x7f").should == Encoding::UTF_8
    end

    it "returns nil when the second's Encoding is BINARY but not ASCII only" do
      Encoding.compatible?(@str, "\xff").should be_nil
    end

    it "returns nil when the second's Encoding is invalid and ASCII only" do
      Encoding.compatible?(@str, "\x7f\x7f".dup.force_encoding("utf-16be")).should be_nil
    end

    it "returns nil when the second's Encoding is invalid and not ASCII only" do
      Encoding.compatible?(@str, "\xff\xff".dup.force_encoding("utf-16be")).should be_nil
    end

    it "returns the Encoding when the second's Encoding is invalid but the same as the first" do
      Encoding.compatible?(@str, @str).should == Encoding::UTF_8
    end
  end

  describe "when the first String is empty and the second is not" do
    describe "and the first's Encoding is ASCII compatible" do
      before :each do
        @str = "".dup.force_encoding("utf-8")
      end

      it "returns the first's encoding when the second String is ASCII only" do
        Encoding.compatible?(@str, "def".encode("us-ascii")).should == Encoding::UTF_8
      end

      it "returns the second's encoding when the second String is not ASCII only" do
        Encoding.compatible?(@str, "def".encode("utf-32le")).should == Encoding::UTF_32LE
      end
    end

    describe "when the first's Encoding is not ASCII compatible" do
      before :each do
        @str = "".dup.force_encoding Encoding::UTF_7
      end

      it "returns the second string's encoding" do
        Encoding.compatible?(@str, "def".encode("us-ascii")).should == Encoding::US_ASCII
      end
    end
  end

  describe "when the second String is empty" do
    before :each do
      @str = "abc".dup.force_encoding("utf-7")
    end

    it "returns the first Encoding" do
      Encoding.compatible?(@str, "").should == Encoding::UTF_7
    end
  end

  # Encoding negotiation depends on whether encodings are ASCII-compatible, empty
  # and contain only ASCII characters (that take 7 bits). Check US-ASCII, UTF-8 and
  # BINARY encodings (as most common) as well as an ASCII-compatible, a non-ASCII-compatible and a dummy
  # encodings in all possible combinations.
  describe "compatibility matrix" do

#     Use the following script to regenerate the matrix:
#
#     ```
#       # encoding: binary
#
#       ENCODINGS = [
#         "US-ASCII",
#         "UTF-8",
#         "ASCII-8BIT",
#         "ISO-8859-1",  # ASCII-compatible
#         "UTF-16BE",    # non-ASCII-compatible
#         "ISO-2022-JP"  # dummy
#       ]
#
#       TYPES = [:empty, :"7bits", :non7bits]
#
#       VALUES = {
#         empty: "",
#         :"7bits" => "\x01\x01",
#         non7bits: "\x01\x81"
#       }
#
#       ENCODINGS.product(TYPES, ENCODINGS, TYPES).each do |encoding1, type1, encoding2, type2|
#         value1 = VALUES[type1].dup.force_encoding(encoding1)
#         value2 = VALUES[type2].dup.force_encoding(encoding2)
#
#         result_encoding = Encoding.compatible?(value1, value2)
#
#         puts "[#{encoding1.inspect}, #{value1.inspect}, #{encoding2.inspect}, #{value2.inspect}, #{result_encoding&.name.inspect}],"
#       end
#     ```

    matrix = [
      ["US-ASCII", "", "US-ASCII", "", "US-ASCII"],
      ["US-ASCII", "", "US-ASCII", "\x01\x01", "US-ASCII"],
      ["US-ASCII", "", "US-ASCII", "\x01\x81", "US-ASCII"],
      ["US-ASCII", "", "UTF-8", "", "US-ASCII"],
      ["US-ASCII", "", "UTF-8", "\u0001\u0001", "US-ASCII"],
      ["US-ASCII", "", "UTF-8", "\u0001\x81", "UTF-8"],
      ["US-ASCII", "", "ASCII-8BIT", "", "US-ASCII"],
      ["US-ASCII", "", "ASCII-8BIT", "\x01\x01", "US-ASCII"],
      ["US-ASCII", "", "ASCII-8BIT", "\x01\x81", "ASCII-8BIT"],
      ["US-ASCII", "", "ISO-8859-1", "", "US-ASCII"],
      ["US-ASCII", "", "ISO-8859-1", "\x01\x01", "US-ASCII"],
      ["US-ASCII", "", "ISO-8859-1", "\x01\x81", "ISO-8859-1"],
      ["US-ASCII", "", "UTF-16BE", "", "US-ASCII"],
      ["US-ASCII", "", "UTF-16BE", "\u0101", "UTF-16BE"],
      ["US-ASCII", "", "UTF-16BE", "\u0181", "UTF-16BE"],
      ["US-ASCII", "", "ISO-2022-JP", "", "US-ASCII"],
      ["US-ASCII", "", "ISO-2022-JP", "\x01\x01", "ISO-2022-JP"],
      ["US-ASCII", "", "ISO-2022-JP", "\x01\x81", "ISO-2022-JP"],
      ["US-ASCII", "\x01\x01", "US-ASCII", "", "US-ASCII"],
      ["US-ASCII", "\x01\x01", "US-ASCII", "\x01\x01", "US-ASCII"],
      ["US-ASCII", "\x01\x01", "US-ASCII", "\x01\x81", "US-ASCII"],
      ["US-ASCII", "\x01\x01", "UTF-8", "", "US-ASCII"],
      ["US-ASCII", "\x01\x01", "UTF-8", "\u0001\u0001", "US-ASCII"],
      ["US-ASCII", "\x01\x01", "UTF-8", "\u0001\x81", "UTF-8"],
      ["US-ASCII", "\x01\x01", "ASCII-8BIT", "", "US-ASCII"],
      ["US-ASCII", "\x01\x01", "ASCII-8BIT", "\x01\x01", "US-ASCII"],
      ["US-ASCII", "\x01\x01", "ASCII-8BIT", "\x01\x81", "ASCII-8BIT"],
      ["US-ASCII", "\x01\x01", "ISO-8859-1", "", "US-ASCII"],
      ["US-ASCII", "\x01\x01", "ISO-8859-1", "\x01\x01", "US-ASCII"],
      ["US-ASCII", "\x01\x01", "ISO-8859-1", "\x01\x81", "ISO-8859-1"],
      ["US-ASCII", "\x01\x01", "UTF-16BE", "", "US-ASCII"],
      ["US-ASCII", "\x01\x01", "UTF-16BE", "\u0101", nil],
      ["US-ASCII", "\x01\x01", "UTF-16BE", "\u0181", nil],
      ["US-ASCII", "\x01\x01", "ISO-2022-JP", "", "US-ASCII"],
      ["US-ASCII", "\x01\x01", "ISO-2022-JP", "\x01\x01", nil],
      ["US-ASCII", "\x01\x01", "ISO-2022-JP", "\x01\x81", nil],
      ["US-ASCII", "\x01\x81", "US-ASCII", "", "US-ASCII"],
      ["US-ASCII", "\x01\x81", "US-ASCII", "\x01\x01", "US-ASCII"],
      ["US-ASCII", "\x01\x81", "US-ASCII", "\x01\x81", "US-ASCII"],
      ["US-ASCII", "\x01\x81", "UTF-8", "", "US-ASCII"],
      ["US-ASCII", "\x01\x81", "UTF-8", "\u0001\u0001", "US-ASCII"],
      ["US-ASCII", "\x01\x81", "UTF-8", "\u0001\x81", nil],
      ["US-ASCII", "\x01\x81", "ASCII-8BIT", "", "US-ASCII"],
      ["US-ASCII", "\x01\x81", "ASCII-8BIT", "\x01\x01", "US-ASCII"],
      ["US-ASCII", "\x01\x81", "ASCII-8BIT", "\x01\x81", nil],
      ["US-ASCII", "\x01\x81", "ISO-8859-1", "", "US-ASCII"],
      ["US-ASCII", "\x01\x81", "ISO-8859-1", "\x01\x01", "US-ASCII"],
      ["US-ASCII", "\x01\x81", "ISO-8859-1", "\x01\x81", nil],
      ["US-ASCII", "\x01\x81", "UTF-16BE", "", "US-ASCII"],
      ["US-ASCII", "\x01\x81", "UTF-16BE", "\u0101", nil],
      ["US-ASCII", "\x01\x81", "UTF-16BE", "\u0181", nil],
      ["US-ASCII", "\x01\x81", "ISO-2022-JP", "", "US-ASCII"],
      ["US-ASCII", "\x01\x81", "ISO-2022-JP", "\x01\x01", nil],
      ["US-ASCII", "\x01\x81", "ISO-2022-JP", "\x01\x81", nil],
      ["UTF-8", "", "US-ASCII", "", "UTF-8"],
      ["UTF-8", "", "US-ASCII", "\x01\x01", "UTF-8"],
      ["UTF-8", "", "US-ASCII", "\x01\x81", "US-ASCII"],
      ["UTF-8", "", "UTF-8", "", "UTF-8"],
      ["UTF-8", "", "UTF-8", "\u0001\u0001", "UTF-8"],
      ["UTF-8", "", "UTF-8", "\u0001\x81", "UTF-8"],
      ["UTF-8", "", "ASCII-8BIT", "", "UTF-8"],
      ["UTF-8", "", "ASCII-8BIT", "\x01\x01", "UTF-8"],
      ["UTF-8", "", "ASCII-8BIT", "\x01\x81", "ASCII-8BIT"],
      ["UTF-8", "", "ISO-8859-1", "", "UTF-8"],
      ["UTF-8", "", "ISO-8859-1", "\x01\x01", "UTF-8"],
      ["UTF-8", "", "ISO-8859-1", "\x01\x81", "ISO-8859-1"],
      ["UTF-8", "", "UTF-16BE", "", "UTF-8"],
      ["UTF-8", "", "UTF-16BE", "\u0101", "UTF-16BE"],
      ["UTF-8", "", "UTF-16BE", "\u0181", "UTF-16BE"],
      ["UTF-8", "", "ISO-2022-JP", "", "UTF-8"],
      ["UTF-8", "", "ISO-2022-JP", "\x01\x01", "ISO-2022-JP"],
      ["UTF-8", "", "ISO-2022-JP", "\x01\x81", "ISO-2022-JP"],
      ["UTF-8", "\u0001\u0001", "US-ASCII", "", "UTF-8"],
      ["UTF-8", "\u0001\u0001", "US-ASCII", "\x01\x01", "UTF-8"],
      ["UTF-8", "\u0001\u0001", "US-ASCII", "\x01\x81", "US-ASCII"],
      ["UTF-8", "\u0001\u0001", "UTF-8", "", "UTF-8"],
      ["UTF-8", "\u0001\u0001", "UTF-8", "\u0001\u0001", "UTF-8"],
      ["UTF-8", "\u0001\u0001", "UTF-8", "\u0001\x81", "UTF-8"],
      ["UTF-8", "\u0001\u0001", "ASCII-8BIT", "", "UTF-8"],
      ["UTF-8", "\u0001\u0001", "ASCII-8BIT", "\x01\x01", "UTF-8"],
      ["UTF-8", "\u0001\u0001", "ASCII-8BIT", "\x01\x81", "ASCII-8BIT"],
      ["UTF-8", "\u0001\u0001", "ISO-8859-1", "", "UTF-8"],
      ["UTF-8", "\u0001\u0001", "ISO-8859-1", "\x01\x01", "UTF-8"],
      ["UTF-8", "\u0001\u0001", "ISO-8859-1", "\x01\x81", "ISO-8859-1"],
      ["UTF-8", "\u0001\u0001", "UTF-16BE", "", "UTF-8"],
      ["UTF-8", "\u0001\u0001", "UTF-16BE", "\u0101", nil],
      ["UTF-8", "\u0001\u0001", "UTF-16BE", "\u0181", nil],
      ["UTF-8", "\u0001\u0001", "ISO-2022-JP", "", "UTF-8"],
      ["UTF-8", "\u0001\u0001", "ISO-2022-JP", "\x01\x01", nil],
      ["UTF-8", "\u0001\u0001", "ISO-2022-JP", "\x01\x81", nil],
      ["UTF-8", "\u0001\x81", "US-ASCII", "", "UTF-8"],
      ["UTF-8", "\u0001\x81", "US-ASCII", "\x01\x01", "UTF-8"],
      ["UTF-8", "\u0001\x81", "US-ASCII", "\x01\x81", nil],
      ["UTF-8", "\u0001\x81", "UTF-8", "", "UTF-8"],
      ["UTF-8", "\u0001\x81", "UTF-8", "\u0001\u0001", "UTF-8"],
      ["UTF-8", "\u0001\x81", "UTF-8", "\u0001\x81", "UTF-8"],
      ["UTF-8", "\u0001\x81", "ASCII-8BIT", "", "UTF-8"],
      ["UTF-8", "\u0001\x81", "ASCII-8BIT", "\x01\x01", "UTF-8"],
      ["UTF-8", "\u0001\x81", "ASCII-8BIT", "\x01\x81", nil],
      ["UTF-8", "\u0001\x81", "ISO-8859-1", "", "UTF-8"],
      ["UTF-8", "\u0001\x81", "ISO-8859-1", "\x01\x01", "UTF-8"],
      ["UTF-8", "\u0001\x81", "ISO-8859-1", "\x01\x81", nil],
      ["UTF-8", "\u0001\x81", "UTF-16BE", "", "UTF-8"],
      ["UTF-8", "\u0001\x81", "UTF-16BE", "\u0101", nil],
      ["UTF-8", "\u0001\x81", "UTF-16BE", "\u0181", nil],
      ["UTF-8", "\u0001\x81", "ISO-2022-JP", "", "UTF-8"],
      ["UTF-8", "\u0001\x81", "ISO-2022-JP", "\x01\x01", nil],
      ["UTF-8", "\u0001\x81", "ISO-2022-JP", "\x01\x81", nil],
      ["ASCII-8BIT", "", "US-ASCII", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "", "US-ASCII", "\x01\x01", "ASCII-8BIT"],
      ["ASCII-8BIT", "", "US-ASCII", "\x01\x81", "US-ASCII"],
      ["ASCII-8BIT", "", "UTF-8", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "", "UTF-8", "\u0001\u0001", "ASCII-8BIT"],
      ["ASCII-8BIT", "", "UTF-8", "\u0001\x81", "UTF-8"],
      ["ASCII-8BIT", "", "ASCII-8BIT", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "", "ASCII-8BIT", "\x01\x01", "ASCII-8BIT"],
      ["ASCII-8BIT", "", "ASCII-8BIT", "\x01\x81", "ASCII-8BIT"],
      ["ASCII-8BIT", "", "ISO-8859-1", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "", "ISO-8859-1", "\x01\x01", "ASCII-8BIT"],
      ["ASCII-8BIT", "", "ISO-8859-1", "\x01\x81", "ISO-8859-1"],
      ["ASCII-8BIT", "", "UTF-16BE", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "", "UTF-16BE", "\u0101", "UTF-16BE"],
      ["ASCII-8BIT", "", "UTF-16BE", "\u0181", "UTF-16BE"],
      ["ASCII-8BIT", "", "ISO-2022-JP", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "", "ISO-2022-JP", "\x01\x01", "ISO-2022-JP"],
      ["ASCII-8BIT", "", "ISO-2022-JP", "\x01\x81", "ISO-2022-JP"],
      ["ASCII-8BIT", "\x01\x01", "US-ASCII", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x01", "US-ASCII", "\x01\x01", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x01", "US-ASCII", "\x01\x81", "US-ASCII"],
      ["ASCII-8BIT", "\x01\x01", "UTF-8", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x01", "UTF-8", "\u0001\u0001", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x01", "UTF-8", "\u0001\x81", "UTF-8"],
      ["ASCII-8BIT", "\x01\x01", "ASCII-8BIT", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x01", "ASCII-8BIT", "\x01\x01", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x01", "ASCII-8BIT", "\x01\x81", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x01", "ISO-8859-1", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x01", "ISO-8859-1", "\x01\x01", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x01", "ISO-8859-1", "\x01\x81", "ISO-8859-1"],
      ["ASCII-8BIT", "\x01\x01", "UTF-16BE", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x01", "UTF-16BE", "\u0101", nil],
      ["ASCII-8BIT", "\x01\x01", "UTF-16BE", "\u0181", nil],
      ["ASCII-8BIT", "\x01\x01", "ISO-2022-JP", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x01", "ISO-2022-JP", "\x01\x01", nil],
      ["ASCII-8BIT", "\x01\x01", "ISO-2022-JP", "\x01\x81", nil],
      ["ASCII-8BIT", "\x01\x81", "US-ASCII", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x81", "US-ASCII", "\x01\x01", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x81", "US-ASCII", "\x01\x81", nil],
      ["ASCII-8BIT", "\x01\x81", "UTF-8", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x81", "UTF-8", "\u0001\u0001", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x81", "UTF-8", "\u0001\x81", nil],
      ["ASCII-8BIT", "\x01\x81", "ASCII-8BIT", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x81", "ASCII-8BIT", "\x01\x01", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x81", "ASCII-8BIT", "\x01\x81", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x81", "ISO-8859-1", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x81", "ISO-8859-1", "\x01\x01", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x81", "ISO-8859-1", "\x01\x81", nil],
      ["ASCII-8BIT", "\x01\x81", "UTF-16BE", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x81", "UTF-16BE", "\u0101", nil],
      ["ASCII-8BIT", "\x01\x81", "UTF-16BE", "\u0181", nil],
      ["ASCII-8BIT", "\x01\x81", "ISO-2022-JP", "", "ASCII-8BIT"],
      ["ASCII-8BIT", "\x01\x81", "ISO-2022-JP", "\x01\x01", nil],
      ["ASCII-8BIT", "\x01\x81", "ISO-2022-JP", "\x01\x81", nil],
      ["ISO-8859-1", "", "US-ASCII", "", "ISO-8859-1"],
      ["ISO-8859-1", "", "US-ASCII", "\x01\x01", "ISO-8859-1"],
      ["ISO-8859-1", "", "US-ASCII", "\x01\x81", "US-ASCII"],
      ["ISO-8859-1", "", "UTF-8", "", "ISO-8859-1"],
      ["ISO-8859-1", "", "UTF-8", "\u0001\u0001", "ISO-8859-1"],
      ["ISO-8859-1", "", "UTF-8", "\u0001\x81", "UTF-8"],
      ["ISO-8859-1", "", "ASCII-8BIT", "", "ISO-8859-1"],
      ["ISO-8859-1", "", "ASCII-8BIT", "\x01\x01", "ISO-8859-1"],
      ["ISO-8859-1", "", "ASCII-8BIT", "\x01\x81", "ASCII-8BIT"],
      ["ISO-8859-1", "", "ISO-8859-1", "", "ISO-8859-1"],
      ["ISO-8859-1", "", "ISO-8859-1", "\x01\x01", "ISO-8859-1"],
      ["ISO-8859-1", "", "ISO-8859-1", "\x01\x81", "ISO-8859-1"],
      ["ISO-8859-1", "", "UTF-16BE", "", "ISO-8859-1"],
      ["ISO-8859-1", "", "UTF-16BE", "\u0101", "UTF-16BE"],
      ["ISO-8859-1", "", "UTF-16BE", "\u0181", "UTF-16BE"],
      ["ISO-8859-1", "", "ISO-2022-JP", "", "ISO-8859-1"],
      ["ISO-8859-1", "", "ISO-2022-JP", "\x01\x01", "ISO-2022-JP"],
      ["ISO-8859-1", "", "ISO-2022-JP", "\x01\x81", "ISO-2022-JP"],
      ["ISO-8859-1", "\x01\x01", "US-ASCII", "", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x01", "US-ASCII", "\x01\x01", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x01", "US-ASCII", "\x01\x81", "US-ASCII"],
      ["ISO-8859-1", "\x01\x01", "UTF-8", "", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x01", "UTF-8", "\u0001\u0001", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x01", "UTF-8", "\u0001\x81", "UTF-8"],
      ["ISO-8859-1", "\x01\x01", "ASCII-8BIT", "", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x01", "ASCII-8BIT", "\x01\x01", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x01", "ASCII-8BIT", "\x01\x81", "ASCII-8BIT"],
      ["ISO-8859-1", "\x01\x01", "ISO-8859-1", "", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x01", "ISO-8859-1", "\x01\x01", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x01", "ISO-8859-1", "\x01\x81", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x01", "UTF-16BE", "", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x01", "UTF-16BE", "\u0101", nil],
      ["ISO-8859-1", "\x01\x01", "UTF-16BE", "\u0181", nil],
      ["ISO-8859-1", "\x01\x01", "ISO-2022-JP", "", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x01", "ISO-2022-JP", "\x01\x01", nil],
      ["ISO-8859-1", "\x01\x01", "ISO-2022-JP", "\x01\x81", nil],
      ["ISO-8859-1", "\x01\x81", "US-ASCII", "", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x81", "US-ASCII", "\x01\x01", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x81", "US-ASCII", "\x01\x81", nil],
      ["ISO-8859-1", "\x01\x81", "UTF-8", "", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x81", "UTF-8", "\u0001\u0001", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x81", "UTF-8", "\u0001\x81", nil],
      ["ISO-8859-1", "\x01\x81", "ASCII-8BIT", "", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x81", "ASCII-8BIT", "\x01\x01", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x81", "ASCII-8BIT", "\x01\x81", nil],
      ["ISO-8859-1", "\x01\x81", "ISO-8859-1", "", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x81", "ISO-8859-1", "\x01\x01", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x81", "ISO-8859-1", "\x01\x81", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x81", "UTF-16BE", "", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x81", "UTF-16BE", "\u0101", nil],
      ["ISO-8859-1", "\x01\x81", "UTF-16BE", "\u0181", nil],
      ["ISO-8859-1", "\x01\x81", "ISO-2022-JP", "", "ISO-8859-1"],
      ["ISO-8859-1", "\x01\x81", "ISO-2022-JP", "\x01\x01", nil],
      ["ISO-8859-1", "\x01\x81", "ISO-2022-JP", "\x01\x81", nil],
      ["UTF-16BE", "", "US-ASCII", "", "UTF-16BE"],
      ["UTF-16BE", "", "US-ASCII", "\x01\x01", "US-ASCII"],
      ["UTF-16BE", "", "US-ASCII", "\x01\x81", "US-ASCII"],
      ["UTF-16BE", "", "UTF-8", "", "UTF-16BE"],
      ["UTF-16BE", "", "UTF-8", "\u0001\u0001", "UTF-8"],
      ["UTF-16BE", "", "UTF-8", "\u0001\x81", "UTF-8"],
      ["UTF-16BE", "", "ASCII-8BIT", "", "UTF-16BE"],
      ["UTF-16BE", "", "ASCII-8BIT", "\x01\x01", "ASCII-8BIT"],
      ["UTF-16BE", "", "ASCII-8BIT", "\x01\x81", "ASCII-8BIT"],
      ["UTF-16BE", "", "ISO-8859-1", "", "UTF-16BE"],
      ["UTF-16BE", "", "ISO-8859-1", "\x01\x01", "ISO-8859-1"],
      ["UTF-16BE", "", "ISO-8859-1", "\x01\x81", "ISO-8859-1"],
      ["UTF-16BE", "", "UTF-16BE", "", "UTF-16BE"],
      ["UTF-16BE", "", "UTF-16BE", "\u0101", "UTF-16BE"],
      ["UTF-16BE", "", "UTF-16BE", "\u0181", "UTF-16BE"],
      ["UTF-16BE", "", "ISO-2022-JP", "", "UTF-16BE"],
      ["UTF-16BE", "", "ISO-2022-JP", "\x01\x01", "ISO-2022-JP"],
      ["UTF-16BE", "", "ISO-2022-JP", "\x01\x81", "ISO-2022-JP"],
      ["UTF-16BE", "\u0101", "US-ASCII", "", "UTF-16BE"],
      ["UTF-16BE", "\u0101", "US-ASCII", "\x01\x01", nil],
      ["UTF-16BE", "\u0101", "US-ASCII", "\x01\x81", nil],
      ["UTF-16BE", "\u0101", "UTF-8", "", "UTF-16BE"],
      ["UTF-16BE", "\u0101", "UTF-8", "\u0001\u0001", nil],
      ["UTF-16BE", "\u0101", "UTF-8", "\u0001\x81", nil],
      ["UTF-16BE", "\u0101", "ASCII-8BIT", "", "UTF-16BE"],
      ["UTF-16BE", "\u0101", "ASCII-8BIT", "\x01\x01", nil],
      ["UTF-16BE", "\u0101", "ASCII-8BIT", "\x01\x81", nil],
      ["UTF-16BE", "\u0101", "ISO-8859-1", "", "UTF-16BE"],
      ["UTF-16BE", "\u0101", "ISO-8859-1", "\x01\x01", nil],
      ["UTF-16BE", "\u0101", "ISO-8859-1", "\x01\x81", nil],
      ["UTF-16BE", "\u0101", "UTF-16BE", "", "UTF-16BE"],
      ["UTF-16BE", "\u0101", "UTF-16BE", "\u0101", "UTF-16BE"],
      ["UTF-16BE", "\u0101", "UTF-16BE", "\u0181", "UTF-16BE"],
      ["UTF-16BE", "\u0101", "ISO-2022-JP", "", "UTF-16BE"],
      ["UTF-16BE", "\u0101", "ISO-2022-JP", "\x01\x01", nil],
      ["UTF-16BE", "\u0101", "ISO-2022-JP", "\x01\x81", nil],
      ["UTF-16BE", "\u0181", "US-ASCII", "", "UTF-16BE"],
      ["UTF-16BE", "\u0181", "US-ASCII", "\x01\x01", nil],
      ["UTF-16BE", "\u0181", "US-ASCII", "\x01\x81", nil],
      ["UTF-16BE", "\u0181", "UTF-8", "", "UTF-16BE"],
      ["UTF-16BE", "\u0181", "UTF-8", "\u0001\u0001", nil],
      ["UTF-16BE", "\u0181", "UTF-8", "\u0001\x81", nil],
      ["UTF-16BE", "\u0181", "ASCII-8BIT", "", "UTF-16BE"],
      ["UTF-16BE", "\u0181", "ASCII-8BIT", "\x01\x01", nil],
      ["UTF-16BE", "\u0181", "ASCII-8BIT", "\x01\x81", nil],
      ["UTF-16BE", "\u0181", "ISO-8859-1", "", "UTF-16BE"],
      ["UTF-16BE", "\u0181", "ISO-8859-1", "\x01\x01", nil],
      ["UTF-16BE", "\u0181", "ISO-8859-1", "\x01\x81", nil],
      ["UTF-16BE", "\u0181", "UTF-16BE", "", "UTF-16BE"],
      ["UTF-16BE", "\u0181", "UTF-16BE", "\u0101", "UTF-16BE"],
      ["UTF-16BE", "\u0181", "UTF-16BE", "\u0181", "UTF-16BE"],
      ["UTF-16BE", "\u0181", "ISO-2022-JP", "", "UTF-16BE"],
      ["UTF-16BE", "\u0181", "ISO-2022-JP", "\x01\x01", nil],
      ["UTF-16BE", "\u0181", "ISO-2022-JP", "\x01\x81", nil],
      ["ISO-2022-JP", "", "US-ASCII", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "", "US-ASCII", "\x01\x01", "US-ASCII"],
      ["ISO-2022-JP", "", "US-ASCII", "\x01\x81", "US-ASCII"],
      ["ISO-2022-JP", "", "UTF-8", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "", "UTF-8", "\u0001\u0001", "UTF-8"],
      ["ISO-2022-JP", "", "UTF-8", "\u0001\x81", "UTF-8"],
      ["ISO-2022-JP", "", "ASCII-8BIT", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "", "ASCII-8BIT", "\x01\x01", "ASCII-8BIT"],
      ["ISO-2022-JP", "", "ASCII-8BIT", "\x01\x81", "ASCII-8BIT"],
      ["ISO-2022-JP", "", "ISO-8859-1", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "", "ISO-8859-1", "\x01\x01", "ISO-8859-1"],
      ["ISO-2022-JP", "", "ISO-8859-1", "\x01\x81", "ISO-8859-1"],
      ["ISO-2022-JP", "", "UTF-16BE", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "", "UTF-16BE", "\u0101", "UTF-16BE"],
      ["ISO-2022-JP", "", "UTF-16BE", "\u0181", "UTF-16BE"],
      ["ISO-2022-JP", "", "ISO-2022-JP", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "", "ISO-2022-JP", "\x01\x01", "ISO-2022-JP"],
      ["ISO-2022-JP", "", "ISO-2022-JP", "\x01\x81", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x01", "US-ASCII", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x01", "US-ASCII", "\x01\x01", nil],
      ["ISO-2022-JP", "\x01\x01", "US-ASCII", "\x01\x81", nil],
      ["ISO-2022-JP", "\x01\x01", "UTF-8", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x01", "UTF-8", "\u0001\u0001", nil],
      ["ISO-2022-JP", "\x01\x01", "UTF-8", "\u0001\x81", nil],
      ["ISO-2022-JP", "\x01\x01", "ASCII-8BIT", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x01", "ASCII-8BIT", "\x01\x01", nil],
      ["ISO-2022-JP", "\x01\x01", "ASCII-8BIT", "\x01\x81", nil],
      ["ISO-2022-JP", "\x01\x01", "ISO-8859-1", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x01", "ISO-8859-1", "\x01\x01", nil],
      ["ISO-2022-JP", "\x01\x01", "ISO-8859-1", "\x01\x81", nil],
      ["ISO-2022-JP", "\x01\x01", "UTF-16BE", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x01", "UTF-16BE", "\u0101", nil],
      ["ISO-2022-JP", "\x01\x01", "UTF-16BE", "\u0181", nil],
      ["ISO-2022-JP", "\x01\x01", "ISO-2022-JP", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x01", "ISO-2022-JP", "\x01\x01", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x01", "ISO-2022-JP", "\x01\x81", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x81", "US-ASCII", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x81", "US-ASCII", "\x01\x01", nil],
      ["ISO-2022-JP", "\x01\x81", "US-ASCII", "\x01\x81", nil],
      ["ISO-2022-JP", "\x01\x81", "UTF-8", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x81", "UTF-8", "\u0001\u0001", nil],
      ["ISO-2022-JP", "\x01\x81", "UTF-8", "\u0001\x81", nil],
      ["ISO-2022-JP", "\x01\x81", "ASCII-8BIT", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x81", "ASCII-8BIT", "\x01\x01", nil],
      ["ISO-2022-JP", "\x01\x81", "ASCII-8BIT", "\x01\x81", nil],
      ["ISO-2022-JP", "\x01\x81", "ISO-8859-1", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x81", "ISO-8859-1", "\x01\x01", nil],
      ["ISO-2022-JP", "\x01\x81", "ISO-8859-1", "\x01\x81", nil],
      ["ISO-2022-JP", "\x01\x81", "UTF-16BE", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x81", "UTF-16BE", "\u0101", nil],
      ["ISO-2022-JP", "\x01\x81", "UTF-16BE", "\u0181", nil],
      ["ISO-2022-JP", "\x01\x81", "ISO-2022-JP", "", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x81", "ISO-2022-JP", "\x01\x01", "ISO-2022-JP"],
      ["ISO-2022-JP", "\x01\x81", "ISO-2022-JP", "\x01\x81", "ISO-2022-JP"],
    ]

    matrix.each do |encoding1, value1, encoding2, value2, compatible_encoding|
      it "returns #{compatible_encoding} for #{value1.inspect} in #{encoding1} and #{value2.inspect} in #{encoding2}" do
        actual_encoding = Encoding.compatible?(value1.dup.force_encoding(encoding1), value2.dup.force_encoding(encoding2))
        actual_encoding&.name.should == compatible_encoding
      end
    end
  end
end

describe "Encoding.compatible? String, Regexp" do
  it "returns US-ASCII if both are US-ASCII" do
    str = "abc".dup.force_encoding("us-ascii")
    Encoding.compatible?(str, /abc/).should == Encoding::US_ASCII
  end

  it "returns the String's Encoding if it is not US-ASCII but both are ASCII only" do
    [ [Encoding, "abc",                     Encoding::BINARY],
      [Encoding, "abc".encode("utf-8"),     Encoding::UTF_8],
      [Encoding, "abc".encode("euc-jp"),    Encoding::EUC_JP],
      [Encoding, "abc".encode("shift_jis"), Encoding::Shift_JIS],
    ].should be_computed_by(:compatible?, /abc/)
  end

  it "returns the String's Encoding if the String is not ASCII only" do
    [ [Encoding, "\xff",                                  Encoding::BINARY],
      [Encoding, "\u3042".encode("utf-8"),                Encoding::UTF_8],
      [Encoding, "\xa4\xa2".dup.force_encoding("euc-jp"),     Encoding::EUC_JP],
      [Encoding, "\x82\xa0".dup.force_encoding("shift_jis"),  Encoding::Shift_JIS],
    ].should be_computed_by(:compatible?, /abc/)
  end
end

describe "Encoding.compatible? String, Symbol" do
  it "returns US-ASCII if both are ASCII only" do
    str = "abc".dup.force_encoding("us-ascii")
    Encoding.compatible?(str, :abc).should == Encoding::US_ASCII
  end

  it "returns the String's Encoding if it is not US-ASCII but both are ASCII only" do
    [ [Encoding, "abc",                     Encoding::BINARY],
      [Encoding, "abc".encode("utf-8"),     Encoding::UTF_8],
      [Encoding, "abc".encode("euc-jp"),    Encoding::EUC_JP],
      [Encoding, "abc".encode("shift_jis"), Encoding::Shift_JIS],
    ].should be_computed_by(:compatible?, :abc)
  end

  it "returns the String's Encoding if the String is not ASCII only" do
    [ [Encoding, "\xff",                                  Encoding::BINARY],
      [Encoding, "\u3042".encode("utf-8"),                Encoding::UTF_8],
      [Encoding, "\xa4\xa2".dup.force_encoding("euc-jp"),     Encoding::EUC_JP],
      [Encoding, "\x82\xa0".dup.force_encoding("shift_jis"),  Encoding::Shift_JIS],
    ].should be_computed_by(:compatible?, :abc)
  end
end

describe "Encoding.compatible? String, Encoding" do
  it "returns nil if the String's encoding is not ASCII compatible" do
    Encoding.compatible?("abc".encode("utf-32le"), Encoding::US_ASCII).should be_nil
  end

  it "returns nil if the Encoding is not ASCII compatible" do
    Encoding.compatible?("abc".encode("us-ascii"), Encoding::UTF_32LE).should be_nil
  end

  it "returns the String's encoding if the Encoding is US-ASCII" do
    [ [Encoding, "\xff",                                  Encoding::BINARY],
      [Encoding, "\u3042".encode("utf-8"),                Encoding::UTF_8],
      [Encoding, "\xa4\xa2".dup.force_encoding("euc-jp"),     Encoding::EUC_JP],
      [Encoding, "\x82\xa0".dup.force_encoding("shift_jis"),  Encoding::Shift_JIS],
    ].should be_computed_by(:compatible?, Encoding::US_ASCII)
  end

  it "returns the Encoding if the String's encoding is ASCII compatible and the String is ASCII only" do
    str = "abc".encode("utf-8")

    Encoding.compatible?(str, Encoding::BINARY).should == Encoding::BINARY
    Encoding.compatible?(str, Encoding::UTF_8).should == Encoding::UTF_8
    Encoding.compatible?(str, Encoding::EUC_JP).should == Encoding::EUC_JP
    Encoding.compatible?(str, Encoding::Shift_JIS).should == Encoding::Shift_JIS
  end

  it "returns nil if the String's encoding is ASCII compatible but the string is not ASCII only" do
    Encoding.compatible?("\u3042".encode("utf-8"), Encoding::BINARY).should be_nil
  end
end

describe "Encoding.compatible? Regexp, String" do
  it "returns US-ASCII if both are US-ASCII" do
    str = "abc".dup.force_encoding("us-ascii")
    Encoding.compatible?(/abc/, str).should == Encoding::US_ASCII
  end

end

describe "Encoding.compatible? Regexp, Regexp" do
  it "returns US-ASCII if both are US-ASCII" do
    Encoding.compatible?(/abc/, /def/).should == Encoding::US_ASCII
  end

  it "returns the first's Encoding if it is not US-ASCII and not ASCII only" do
    [ [Encoding, Regexp.new("\xff"),                                  Encoding::BINARY],
      [Encoding, Regexp.new("\u3042".encode("utf-8")),                Encoding::UTF_8],
      [Encoding, Regexp.new("\xa4\xa2".dup.force_encoding("euc-jp")),     Encoding::EUC_JP],
      [Encoding, Regexp.new("\x82\xa0".dup.force_encoding("shift_jis")),  Encoding::Shift_JIS],
    ].should be_computed_by(:compatible?, /abc/)
  end
end

describe "Encoding.compatible? Regexp, Symbol" do
  it "returns US-ASCII if both are US-ASCII" do
    Encoding.compatible?(/abc/, :def).should == Encoding::US_ASCII
  end

  it "returns the first's Encoding if it is not US-ASCII and not ASCII only" do
    [ [Encoding, Regexp.new("\xff"),                                  Encoding::BINARY],
      [Encoding, Regexp.new("\u3042".encode("utf-8")),                Encoding::UTF_8],
      [Encoding, Regexp.new("\xa4\xa2".dup.force_encoding("euc-jp")),     Encoding::EUC_JP],
      [Encoding, Regexp.new("\x82\xa0".dup.force_encoding("shift_jis")),  Encoding::Shift_JIS],
    ].should be_computed_by(:compatible?, /abc/)
  end
end

describe "Encoding.compatible? Symbol, String" do
  it "returns US-ASCII if both are ASCII only" do
    str = "abc".dup.force_encoding("us-ascii")
    Encoding.compatible?(str, :abc).should == Encoding::US_ASCII
  end
end

describe "Encoding.compatible? Symbol, Regexp" do
  it "returns US-ASCII if both are US-ASCII" do
    Encoding.compatible?(:abc, /def/).should == Encoding::US_ASCII
  end

  it "returns the Regexp's Encoding if it is not US-ASCII and not ASCII only" do
    a = Regexp.new("\xff")
    b = Regexp.new("\u3042".encode("utf-8"))
    c = Regexp.new("\xa4\xa2".dup.force_encoding("euc-jp"))
    d = Regexp.new("\x82\xa0".dup.force_encoding("shift_jis"))

    [ [Encoding, :abc, a, Encoding::BINARY],
      [Encoding, :abc, b, Encoding::UTF_8],
      [Encoding, :abc, c, Encoding::EUC_JP],
      [Encoding, :abc, d, Encoding::Shift_JIS],
    ].should be_computed_by(:compatible?)
  end
end

describe "Encoding.compatible? Symbol, Symbol" do
  it "returns US-ASCII if both are US-ASCII" do
    Encoding.compatible?(:abc, :def).should == Encoding::US_ASCII
  end

  it "returns the first's Encoding if it is not ASCII only" do
    [ [Encoding, "\xff".to_sym,                                  Encoding::BINARY],
      [Encoding, "\u3042".encode("utf-8").to_sym,                Encoding::UTF_8],
      [Encoding, "\xa4\xa2".dup.force_encoding("euc-jp").to_sym,     Encoding::EUC_JP],
      [Encoding, "\x82\xa0".dup.force_encoding("shift_jis").to_sym,  Encoding::Shift_JIS],
    ].should be_computed_by(:compatible?, :abc)
  end
end

describe "Encoding.compatible? Encoding, Encoding" do
  it "returns nil if one of the encodings is a dummy encoding" do
    [ [Encoding, Encoding::UTF_7, Encoding::US_ASCII,   nil],
      [Encoding, Encoding::US_ASCII, Encoding::UTF_7,   nil],
      [Encoding, Encoding::EUC_JP, Encoding::UTF_7,     nil],
      [Encoding, Encoding::UTF_7, Encoding::EUC_JP,     nil],
      [Encoding, Encoding::UTF_7, Encoding::BINARY, nil],
      [Encoding, Encoding::BINARY, Encoding::UTF_7, nil],
    ].should be_computed_by(:compatible?)
  end

  it "returns nil if one of the encodings is not US-ASCII" do
    [ [Encoding, Encoding::UTF_8, Encoding::BINARY,   nil],
      [Encoding, Encoding::BINARY, Encoding::UTF_8,   nil],
      [Encoding, Encoding::BINARY, Encoding::EUC_JP,  nil],
      [Encoding, Encoding::Shift_JIS, Encoding::EUC_JP,   nil],
    ].should be_computed_by(:compatible?)
  end

  it "returns the first if the second is US-ASCII" do
    [ [Encoding, Encoding::UTF_8, Encoding::US_ASCII,       Encoding::UTF_8],
      [Encoding, Encoding::EUC_JP, Encoding::US_ASCII,      Encoding::EUC_JP],
      [Encoding, Encoding::Shift_JIS, Encoding::US_ASCII,   Encoding::Shift_JIS],
      [Encoding, Encoding::BINARY, Encoding::US_ASCII,  Encoding::BINARY],
    ].should be_computed_by(:compatible?)
  end

  it "returns the Encoding if both are the same" do
    [ [Encoding, Encoding::UTF_8, Encoding::UTF_8,            Encoding::UTF_8],
      [Encoding, Encoding::US_ASCII, Encoding::US_ASCII,      Encoding::US_ASCII],
      [Encoding, Encoding::BINARY, Encoding::BINARY,  Encoding::BINARY],
      [Encoding, Encoding::UTF_7, Encoding::UTF_7,            Encoding::UTF_7],
    ].should be_computed_by(:compatible?)
  end
end

describe "Encoding.compatible? Object, Object" do
  it "returns nil for Object, String" do
    Encoding.compatible?(Object.new, "abc").should be_nil
  end

  it "returns nil for Object, Regexp" do
    Encoding.compatible?(Object.new, /./).should be_nil
  end

  it "returns nil for Object, Symbol" do
    Encoding.compatible?(Object.new, :sym).should be_nil
  end

  it "returns nil for String, Object" do
    Encoding.compatible?("abc", Object.new).should be_nil
  end

  it "returns nil for Regexp, Object" do
    Encoding.compatible?(/./, Object.new).should be_nil
  end

  it "returns nil for Symbol, Object" do
    Encoding.compatible?(:sym, Object.new).should be_nil
  end
end

describe "Encoding.compatible? nil, nil" do
  it "returns nil" do
    Encoding.compatible?(nil, nil).should be_nil
  end
end
