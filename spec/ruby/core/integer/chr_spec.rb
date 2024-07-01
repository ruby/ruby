require_relative '../../spec_helper'

describe "Integer#chr without argument" do
  it "returns a String" do
    17.chr.should be_an_instance_of(String)
  end

  it "returns a new String for each call" do
    82.chr.should_not equal(82.chr)
  end

  it "raises a RangeError is self is less than 0" do
    -> { -1.chr }.should raise_error(RangeError, /-1 out of char range/)
    -> { (-bignum_value).chr }.should raise_error(RangeError, /bignum out of char range/)
  end

  it "raises a RangeError if self is too large" do
    -> { 2206368128.chr(Encoding::UTF_8) }.should raise_error(RangeError, /2206368128 out of char range/)
  end

  describe "when Encoding.default_internal is nil" do
    describe "and self is between 0 and 127 (inclusive)" do
      it "returns a US-ASCII String" do
        (0..127).each do |c|
          c.chr.encoding.should == Encoding::US_ASCII
        end
      end

      it "returns a String encoding self interpreted as a US-ASCII codepoint" do
        (0..127).each do |c|
          c.chr.bytes.to_a.should == [c]
        end
      end
    end

    describe "and self is between 128 and 255 (inclusive)" do
      it "returns a binary String" do
        (128..255).each do |c|
          c.chr.encoding.should == Encoding::BINARY
        end
      end

      it "returns a String containing self interpreted as a byte" do
        (128..255).each do |c|
          c.chr.bytes.to_a.should == [c]
        end
      end
    end

    it "raises a RangeError is self is greater than 255" do
      -> { 256.chr }.should raise_error(RangeError, /256 out of char range/)
      -> { bignum_value.chr }.should raise_error(RangeError, /bignum out of char range/)
    end
  end

  describe "when Encoding.default_internal is not nil" do
    before do
      @default_internal = Encoding.default_internal
    end

    after do
      Encoding.default_internal = @default_internal
    end

    describe "and self is between 0 and 127 (inclusive)" do
      it "returns a US-ASCII String" do
        (0..127).each do |c|
          Encoding.default_internal = Encoding::UTF_8
          c.chr.encoding.should == Encoding::US_ASCII

          Encoding.default_internal = Encoding::SHIFT_JIS
          c.chr.encoding.should == Encoding::US_ASCII
        end
      end

      it "returns a String encoding self interpreted as a US-ASCII codepoint" do
        (0..127).each do |c|
          Encoding.default_internal = Encoding::UTF_8
          c.chr.bytes.to_a.should == [c]

          Encoding.default_internal = Encoding::SHIFT_JIS
          c.chr.bytes.to_a.should == [c]
        end
      end
    end

    describe "and self is between 128 and 255 (inclusive)" do
      it "returns a binary String" do
        (128..255).each do |c|
          Encoding.default_internal = Encoding::UTF_8
          c.chr.encoding.should == Encoding::BINARY

          Encoding.default_internal = Encoding::SHIFT_JIS
          c.chr.encoding.should == Encoding::BINARY
        end
      end

      it "returns a String containing self interpreted as a byte" do
        (128..255).each do |c|
          Encoding.default_internal = Encoding::UTF_8
          c.chr.bytes.to_a.should == [c]

          Encoding.default_internal = Encoding::SHIFT_JIS
          c.chr.bytes.to_a.should == [c]
        end
      end
    end

    describe "and self is greater than 255" do
      it "returns a String with the default internal encoding" do
        Encoding.default_internal = Encoding::UTF_8
        0x0100.chr.encoding.should == Encoding::UTF_8
        0x3000.chr.encoding.should == Encoding::UTF_8

        Encoding.default_internal = Encoding::SHIFT_JIS
        0x8140.chr.encoding.should == Encoding::SHIFT_JIS
        0xFC4B.chr.encoding.should == Encoding::SHIFT_JIS
      end

      it "returns a String encoding self interpreted as a codepoint in the default internal encoding" do
        Encoding.default_internal = Encoding::UTF_8
        0x0100.chr.bytes.to_a.should == [0xC4, 0x80]
        0x3000.chr.bytes.to_a.should == [0xE3, 0x80, 0x80]

        Encoding.default_internal = Encoding::SHIFT_JIS
        0x8140.chr.bytes.to_a.should == [0x81, 0x40] # Smallest assigned CP932 codepoint greater than 255
        0xFC4B.chr.bytes.to_a.should == [0xFC, 0x4B] # Largest assigned CP932 codepoint
      end

      # #5864
      it "raises RangeError if self is invalid as a codepoint in the default internal encoding" do
        [ [0x0100, "US-ASCII"],
          [0x0100, "BINARY"],
          [0x0100, "EUC-JP"],
          [0xA1A0, "EUC-JP"],
          [0x0100, "ISO-8859-9"],
          [620,    "TIS-620"]
        ].each do |integer, encoding_name|
          Encoding.default_internal = Encoding.find(encoding_name)
          -> { integer.chr }.should raise_error(RangeError, /(invalid codepoint|out of char range)/)
        end
      end
    end
  end
end

describe "Integer#chr with an encoding argument" do
  it "returns a String" do
    900.chr(Encoding::UTF_8).should be_an_instance_of(String)
  end

  it "returns a new String for each call" do
    8287.chr(Encoding::UTF_8).should_not equal(8287.chr(Encoding::UTF_8))
  end

  it "accepts a String as an argument" do
    -> { 0xA4A2.chr('euc-jp') }.should_not raise_error
  end

  it "converts a String to an Encoding as Encoding.find does" do
    ['utf-8', 'UTF-8', 'Utf-8'].each do |encoding|
      7894.chr(encoding).encoding.should == Encoding::UTF_8
    end
  end

  # http://redmine.ruby-lang.org/issues/4869
  it "raises a RangeError is self is less than 0" do
    -> { -1.chr(Encoding::UTF_8) }.should raise_error(RangeError, /-1 out of char range/)
    -> { (-bignum_value).chr(Encoding::EUC_JP) }.should raise_error(RangeError, /bignum out of char range/)
  end

  it "raises a RangeError if self is too large" do
    -> { 2206368128.chr(Encoding::UTF_8) }.should raise_error(RangeError, /2206368128 out of char range/)
  end

  it "returns a String with the specified encoding" do
    0x0000.chr(Encoding::US_ASCII).encoding.should == Encoding::US_ASCII
    0x007F.chr(Encoding::US_ASCII).encoding.should == Encoding::US_ASCII

    0x0000.chr(Encoding::BINARY).encoding.should == Encoding::BINARY
    0x007F.chr(Encoding::BINARY).encoding.should == Encoding::BINARY
    0x0080.chr(Encoding::BINARY).encoding.should == Encoding::BINARY
    0x00FF.chr(Encoding::BINARY).encoding.should == Encoding::BINARY

    0x0000.chr(Encoding::UTF_8).encoding.should == Encoding::UTF_8
    0x007F.chr(Encoding::UTF_8).encoding.should == Encoding::UTF_8
    0x0080.chr(Encoding::UTF_8).encoding.should == Encoding::UTF_8
    0x00FF.chr(Encoding::UTF_8).encoding.should == Encoding::UTF_8
    0x0100.chr(Encoding::UTF_8).encoding.should == Encoding::UTF_8
    0x3000.chr(Encoding::UTF_8).encoding.should == Encoding::UTF_8

    0x0000.chr(Encoding::SHIFT_JIS).encoding.should == Encoding::SHIFT_JIS
    0x007F.chr(Encoding::SHIFT_JIS).encoding.should == Encoding::SHIFT_JIS
    0x00A1.chr(Encoding::SHIFT_JIS).encoding.should == Encoding::SHIFT_JIS
    0x00DF.chr(Encoding::SHIFT_JIS).encoding.should == Encoding::SHIFT_JIS
    0x8140.chr(Encoding::SHIFT_JIS).encoding.should == Encoding::SHIFT_JIS
    0xFC4B.chr(Encoding::SHIFT_JIS).encoding.should == Encoding::SHIFT_JIS
  end

  it "returns a String encoding self interpreted as a codepoint in the specified encoding" do
    0x0000.chr(Encoding::US_ASCII).bytes.to_a.should == [0x00]
    0x007F.chr(Encoding::US_ASCII).bytes.to_a.should == [0x7F]

    0x0000.chr(Encoding::BINARY).bytes.to_a.should == [0x00]
    0x007F.chr(Encoding::BINARY).bytes.to_a.should == [0x7F]
    0x0080.chr(Encoding::BINARY).bytes.to_a.should == [0x80]
    0x00FF.chr(Encoding::BINARY).bytes.to_a.should == [0xFF]

    0x0000.chr(Encoding::UTF_8).bytes.to_a.should == [0x00]
    0x007F.chr(Encoding::UTF_8).bytes.to_a.should == [0x7F]
    0x0080.chr(Encoding::UTF_8).bytes.to_a.should == [0xC2, 0x80]
    0x00FF.chr(Encoding::UTF_8).bytes.to_a.should == [0xC3, 0xBF]
    0x0100.chr(Encoding::UTF_8).bytes.to_a.should == [0xC4, 0x80]
    0x3000.chr(Encoding::UTF_8).bytes.to_a.should == [0xE3, 0x80, 0x80]

    0x0000.chr(Encoding::SHIFT_JIS).bytes.to_a.should == [0x00]
    0x007F.chr(Encoding::SHIFT_JIS).bytes.to_a.should == [0x7F]
    0x00A1.chr(Encoding::SHIFT_JIS).bytes.to_a.should == [0xA1]
    0x00DF.chr(Encoding::SHIFT_JIS).bytes.to_a.should == [0xDF]
    0x8140.chr(Encoding::SHIFT_JIS).bytes.to_a.should == [0x81, 0x40] # Smallest assigned CP932 codepoint greater than 255
    0xFC4B.chr(Encoding::SHIFT_JIS).bytes.to_a.should == [0xFC, 0x4B] # Largest assigned CP932 codepoint
  end

  # #5864
  it "raises RangeError if self is invalid as a codepoint in the specified encoding" do
    -> { 0x80.chr("US-ASCII") }.should raise_error(RangeError)
    -> { 0x0100.chr("BINARY") }.should raise_error(RangeError)
    -> { 0x0100.chr("EUC-JP") }.should raise_error(RangeError)
    -> { 0xA1A0.chr("EUC-JP") }.should raise_error(RangeError)
    -> { 0xA1.chr("EUC-JP") }.should raise_error(RangeError)
    -> { 0x80.chr("SHIFT_JIS") }.should raise_error(RangeError)
    -> { 0xE0.chr("SHIFT_JIS") }.should raise_error(RangeError)
    -> { 0x0100.chr("ISO-8859-9") }.should raise_error(RangeError)
    -> { 620.chr("TIS-620") }.should raise_error(RangeError)
    # UTF-16 surrogate range
    -> { 0xD800.chr("UTF-8") }.should raise_error(RangeError)
    -> { 0xDBFF.chr("UTF-8") }.should raise_error(RangeError)
    -> { 0xDC00.chr("UTF-8") }.should raise_error(RangeError)
    -> { 0xDFFF.chr("UTF-8") }.should raise_error(RangeError)
    # UTF-16 surrogate range
    -> { 0xD800.chr("UTF-16") }.should raise_error(RangeError)
    -> { 0xDBFF.chr("UTF-16") }.should raise_error(RangeError)
    -> { 0xDC00.chr("UTF-16") }.should raise_error(RangeError)
    -> { 0xDFFF.chr("UTF-16") }.should raise_error(RangeError)
  end

  it 'returns a String encoding self interpreted as a codepoint in the CESU-8 encoding' do
    # see more details here https://en.wikipedia.org/wiki/CESU-8
    # code points from U+0000 to U+FFFF is encoded in the same way as in UTF-8
    0x0045.chr(Encoding::CESU_8).bytes.should == 0x0045.chr(Encoding::UTF_8).bytes

    # code points in range from U+10000 to U+10FFFF is CESU-8 data containing a 6-byte surrogate pair,
    # which decodes to a 4-byte UTF-8 string
    0x10400.chr(Encoding::CESU_8).bytes.should != 0x10400.chr(Encoding::UTF_8).bytes
    0x10400.chr(Encoding::CESU_8).bytes.to_a.should == [0xED, 0xA0, 0x81, 0xED, 0xB0, 0x80]
  end
end
