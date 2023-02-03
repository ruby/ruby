# -*- encoding: utf-8 -*-
require_relative 'spec_helper'
require_relative 'fixtures/encoding'

load_extension('encoding')

describe :rb_enc_get_index, shared: true do
  it "returns the index of the encoding of a String" do
    @s.send(@method, "string").should >= 0
  end

  it "returns the index of the encoding of a Regexp" do
    @s.send(@method, /regexp/).should >= 0
  end
end

describe :rb_enc_set_index, shared: true do
  it "sets the object's encoding to the Encoding specified by the index" do
    obj = "abc"
    result = @s.send(@method, obj, 2)

    # This is used because indexes should be considered implementation
    # dependent. So a pair is returned:
    #   [rb_enc_find_index() -> name, rb_enc_get(obj) -> name]
    result.first.should == result.last
  end

  it "associates an encoding with a subclass of String" do
    str = CApiEncodingSpecs::S.new "abc"
    result = @s.send(@method, str, 1)
    result.first.should == result.last
  end

  it "raises an ArgumentError for a non-encoding capable object" do
    obj = Object.new
    -> {
      result = @s.send(@method, obj, 1)
    }.should raise_error(ArgumentError, "cannot set encoding on non-encoding capable object")
  end
end

describe "C-API Encoding function" do
  @n = 0

  before :each do
    @s = CApiEncodingSpecs.new
  end

  describe "rb_enc_alias" do
    it "creates an alias for an existing Encoding" do
      name = "ZOMGWTFBBQ#{@n += 1}"
      @s.rb_enc_alias(name, "UTF-8").should >= 0
      Encoding.find(name).name.should == "UTF-8"
    end
  end

  describe "rb_enc_codelen" do
    it "returns the correct length for the given codepoint" do
      @s.rb_enc_codelen(0x24, Encoding::UTF_8).should == 1
      @s.rb_enc_codelen(0xA2, Encoding::UTF_8).should == 2
      @s.rb_enc_codelen(0x20AC, Encoding::UTF_8).should == 3
      @s.rb_enc_codelen(0x24B62, Encoding::UTF_8).should == 4
    end
  end

  describe "rb_enc_strlen" do
    before :each do
      @str = 'こにちわ' # Each codepoint in this string is 3 bytes in UTF-8
    end

    it "returns the correct string length for the encoding" do
      @s.rb_enc_strlen(@str, @str.bytesize, Encoding::UTF_8).should == 4
      @s.rb_enc_strlen(@str, @str.bytesize, Encoding::BINARY).should == 12
    end

    it "returns the string length based on a fixed-width encoding's character length, even if the encoding is incompatible" do
      @s.rb_enc_strlen(@str, @str.bytesize, Encoding::UTF_16BE).should == 6
      @s.rb_enc_strlen(@str, @str.bytesize, Encoding::UTF_16LE).should == 6
      @s.rb_enc_strlen(@str, @str.bytesize, Encoding::UTF_32BE).should == 3
      @s.rb_enc_strlen(@str, @str.bytesize, Encoding::UTF_32LE).should == 3
    end

    it "does not consider strings to be NUL-terminated" do
      s = "abc\0def"
      @s.rb_enc_strlen(s, s.bytesize, Encoding::US_ASCII).should == 7
      @s.rb_enc_strlen(s, s.bytesize, Encoding::UTF_8).should == 7
    end

    describe "handles broken strings" do
      it "combines valid character and invalid character counts in UTF-8" do
        # The result is 3 because `rb_enc_strlen` counts the first valid character and then adds
        # the byte count for the invalid character that follows for 1 + 2.
        @s.rb_enc_strlen(@str, 5, Encoding::UTF_8).should == 3
      end

      it "combines valid character and invalid character counts in UTF-16" do
        @s.rb_enc_strlen(@str, 5, Encoding::UTF_16BE).should == 3
      end

      it "rounds up for fixed-width encodings" do
        @s.rb_enc_strlen(@str, 7, Encoding::UTF_32BE).should == 2
        @s.rb_enc_strlen(@str, 7, Encoding::UTF_32LE).should == 2
        @s.rb_enc_strlen(@str, 5, Encoding::BINARY).should == 5
      end
    end
  end

  describe "rb_enc_find" do
    it "returns the encoding of an Encoding" do
      @s.rb_enc_find("UTF-8").should == "UTF-8"
    end

    it "returns the encoding of an Encoding specified with lower case" do
      @s.rb_enc_find("utf-8").should == "UTF-8"
    end
  end

  describe "rb_enc_find_index" do
    it "returns the index of an Encoding" do
      @s.rb_enc_find_index("UTF-8").should >= 0
    end

    it "returns the index of an Encoding specified with lower case" do
      @s.rb_enc_find_index("utf-8").should >= 0
    end

    it "returns -1 for an non existing encoding" do
      @s.rb_enc_find_index("non-existent-encoding").should == -1
    end
  end

  describe "rb_enc_isalnum" do
    it "returns non-zero for alpha-numeric characters" do
      @s.rb_enc_isalnum("a".ord, Encoding::US_ASCII).should == true
      @s.rb_enc_isalnum("2".ord, Encoding::US_ASCII).should == true
      @s.rb_enc_isalnum("a".ord, Encoding::UTF_8).should == true
      @s.rb_enc_isalnum("2".ord, Encoding::UTF_8).should == true
      @s.rb_enc_isalnum("é".encode(Encoding::ISO_8859_1).ord, Encoding::ISO_8859_1).should == true
    end

    it "returns zero for non alpha-numeric characters" do
      @s.rb_enc_isalnum("-".ord, Encoding::US_ASCII).should == false
      @s.rb_enc_isalnum(" ".ord, Encoding::US_ASCII).should == false
      @s.rb_enc_isalnum("-".ord, Encoding::UTF_8).should == false
      @s.rb_enc_isalnum(" ".ord, Encoding::UTF_8).should == false
    end
  end

  describe "rb_enc_isspace" do
    it "returns non-zero for space characters" do
      @s.rb_enc_isspace(" ".ord, Encoding::US_ASCII).should == true
      @s.rb_enc_isspace(" ".ord, Encoding::UTF_8).should == true
    end

    it "returns zero for non space characters" do
      @s.rb_enc_isspace("-".ord, Encoding::US_ASCII).should == false
      @s.rb_enc_isspace("A".ord, Encoding::US_ASCII).should == false
      @s.rb_enc_isspace("3".ord, Encoding::US_ASCII).should == false
      @s.rb_enc_isspace("-".ord, Encoding::UTF_8).should == false
      @s.rb_enc_isspace("A".ord, Encoding::UTF_8).should == false
      @s.rb_enc_isspace("3".ord, Encoding::UTF_8).should == false
    end
  end

  describe "rb_enc_from_index" do
    it "returns an Encoding" do
      @s.rb_enc_from_index(0).should be_an_instance_of(String)
    end
  end

  describe "rb_enc_mbc_to_codepoint" do
    it "returns the correct codepoint for the given character and size" do
       @s.rb_enc_mbc_to_codepoint("é").should == 0xE9
    end

    it "returns 0 if p == e" do
      @s.rb_enc_mbc_to_codepoint("").should == 0
    end

    it "returns the raw byte if incomplete character in UTF-8" do
      @s.rb_enc_mbc_to_codepoint("\xC3").should == 0xC3
      @s.rb_enc_mbc_to_codepoint("\x80").should == 0x80
    end
  end

  describe "rb_enc_mbcput" do
    it "writes the correct bytes to the buffer" do
      @s.rb_enc_mbcput(0x24, Encoding::UTF_8).should == "$"
      @s.rb_enc_mbcput(0xA2, Encoding::UTF_8).should == "¢"
      @s.rb_enc_mbcput(0x20AC, Encoding::UTF_8).should == "€"
      @s.rb_enc_mbcput(0x24B62, Encoding::UTF_8).should == "𤭢"

      @s.rb_enc_mbcput(0x24, Encoding::UTF_16BE).bytes.should == [0, 0x24]
      @s.rb_enc_mbcput(0x24B62, Encoding::UTF_16LE).bytes.should == [82, 216, 98, 223]
    end
  end

  describe "rb_usascii_encoding" do
    it "returns the encoding for Encoding::US_ASCII" do
      @s.rb_usascii_encoding.should == "US-ASCII"
    end
  end

  describe "rb_ascii8bit_encoding" do
    it "returns the encoding for Encoding::BINARY" do
      @s.rb_ascii8bit_encoding.should == "ASCII-8BIT"
    end
  end

  describe "rb_utf8_encoding" do
    it "returns the encoding for Encoding::UTF_8" do
      @s.rb_utf8_encoding.should == "UTF-8"
    end
  end

  describe "rb_enc_from_encoding" do
    it "returns an Encoding instance from an encoding data structure" do
      @s.rb_enc_from_encoding("UTF-8").should == Encoding::UTF_8
    end
  end

  describe "rb_locale_encoding" do
    it "returns the encoding for the current locale" do
      @s.rb_locale_encoding.should == Encoding.find('locale').name
    end
  end

  describe "rb_filesystem_encoding" do
    it "returns the encoding for the current filesystem" do
      @s.rb_filesystem_encoding.should == Encoding.find('filesystem').name
    end
  end

  describe "rb_enc_get" do
    it "returns the encoding associated with an object" do
      str = "abc".encode Encoding::BINARY
      @s.rb_enc_get(str).should == "ASCII-8BIT"
    end
  end

  describe "rb_enc_precise_mbclen" do
    it "returns the correct length for single byte characters" do
      @s.rb_enc_precise_mbclen("hello", 7).should == 1
      @s.rb_enc_precise_mbclen("hello", 5).should == 1
      @s.rb_enc_precise_mbclen("hello", 1).should == 1
      @s.rb_enc_precise_mbclen("hello", 0).should == -2
      @s.rb_enc_precise_mbclen("hello", -1).should == -2
      @s.rb_enc_precise_mbclen("hello", -5).should == -2
    end

    it "returns the correct length for multi-byte characters" do
      @s.rb_enc_precise_mbclen("ésumé", 2).should == 2
      @s.rb_enc_precise_mbclen("ésumé", 3).should == 2
      @s.rb_enc_precise_mbclen("ésumé", 0).should == -2
      @s.rb_enc_precise_mbclen("ésumé", 1).should == -2
      @s.rb_enc_precise_mbclen("あ", 20).should == 3
      @s.rb_enc_precise_mbclen("あ", 3).should == 3
      @s.rb_enc_precise_mbclen("あ", 2).should == -2
      @s.rb_enc_precise_mbclen("あ", 0).should == -2
      @s.rb_enc_precise_mbclen("あ", -2).should == -2
    end
  end

  describe "rb_obj_encoding" do
    it "returns the encoding associated with an object" do
      str = "abc".encode Encoding::BINARY
      @s.rb_obj_encoding(str).should == Encoding::BINARY
    end
  end

  describe "rb_enc_get_index" do
    it_behaves_like :rb_enc_get_index, :rb_enc_get_index

    it "returns the index of the encoding of a Symbol" do
      @s.rb_enc_get_index(:symbol).should >= 0
    end

    it "returns -1 as the index of nil" do
      @s.rb_enc_get_index(nil).should == -1
    end

    it "returns -1 as the index for immediates" do
      @s.rb_enc_get_index(1).should == -1
    end

    it "returns -1 for an object without an encoding" do
      obj = Object.new
      @s.rb_enc_get_index(obj).should == -1
    end
  end

  describe "rb_enc_set_index" do
    it_behaves_like :rb_enc_set_index, :rb_enc_set_index
  end

  describe "rb_enc_str_new" do
    it "returns a String in US-ASCII encoding when high bits are set" do
      xEE = [0xEE].pack('C').force_encoding('utf-8')
      result = @s.rb_enc_str_new(xEE, 1, Encoding::US_ASCII)
      result.encoding.should equal(Encoding::US_ASCII)
    end
  end

  describe "rb_enc_str_new_cstr" do
    it "creates a new ruby string from a c string literal" do
      result = @s.rb_enc_str_new_cstr_constant(Encoding::US_ASCII)
      result.should  == "test string literal"
      result.encoding.should == Encoding::US_ASCII
    end

    it "creates a new ruby string from a c string variable" do
      result = @s.rb_enc_str_new_cstr("test string", Encoding::US_ASCII)
      result.should == "test string"
      result.encoding.should == Encoding::US_ASCII
    end

    it "when null encoding is given with a c string literal, it creates a new ruby string with ASCII_8BIT encoding" do
      result = @s.rb_enc_str_new_cstr_constant(nil)
      result.should == "test string literal"
      result.encoding.should == Encoding::ASCII_8BIT
    end
  end

  describe "rb_enc_str_coderange" do
    describe "when the encoding is BINARY" do
      it "returns ENC_CODERANGE_7BIT if there are no high bits set" do
        result = @s.rb_enc_str_coderange("abc".force_encoding("binary"))
        result.should == :coderange_7bit
      end

      it "returns ENC_CODERANGE_VALID if there are high bits set" do
        xEE = [0xEE].pack('C').force_encoding('utf-8')
        result = @s.rb_enc_str_coderange(xEE.force_encoding("binary"))
        result.should == :coderange_valid
      end
    end

    describe "when the encoding is UTF-8" do
      it "returns ENC_CODERANGE_7BIT if there are no high bits set" do
        result = @s.rb_enc_str_coderange("abc".force_encoding("utf-8"))
        result.should == :coderange_7bit
      end

      it "returns ENC_CODERANGE_VALID if there are high bits set in a valid string" do
        result = @s.rb_enc_str_coderange("\xE3\x81\x82".force_encoding("utf-8"))
        result.should == :coderange_valid
      end

      it "returns ENC_CODERANGE_BROKEN if there are high bits set in an invalid string" do
        result = @s.rb_enc_str_coderange([0xEE].pack('C').force_encoding("utf-8"))
        result.should == :coderange_broken
      end
    end

    describe "when the encoding is US-ASCII" do
      it "returns ENC_CODERANGE_7BIT if there are no high bits set" do
        result = @s.rb_enc_str_coderange("abc".force_encoding("us-ascii"))
        result.should == :coderange_7bit
      end

      it "returns ENC_CODERANGE_BROKEN if there are high bits set" do
        result = @s.rb_enc_str_coderange([0xEE].pack('C').force_encoding("us-ascii"))
        result.should == :coderange_broken
      end
    end
  end

  describe "MBCLEN_CHARFOUND_P" do
    it "returns non-zero for valid character" do
      @s.MBCLEN_CHARFOUND_P("a".ord).should == 1
    end

    it "returns zero for invalid characters" do
      @s.MBCLEN_CHARFOUND_P(0).should == 0
      @s.MBCLEN_CHARFOUND_P(-1).should == 0
    end
  end

  describe "ENCODING_GET" do
    it_behaves_like :rb_enc_get_index, :ENCODING_GET
  end

  describe "ENCODING_SET" do
    it_behaves_like :rb_enc_set_index, :ENCODING_SET
  end

  describe "ENC_CODERANGE_ASCIIONLY" do
    it "returns true if the object encoding is only ASCII" do
      str = "abc".force_encoding("us-ascii")
      str.valid_encoding? # make sure to set the coderange
      @s.ENC_CODERANGE_ASCIIONLY(str).should be_true
    end

    it "returns false if the object encoding is not ASCII only" do
      str = "ありがとう".force_encoding("utf-8")
      @s.ENC_CODERANGE_ASCIIONLY(str).should be_false
    end
  end

  describe "rb_to_encoding" do
    it "returns the encoding for the Encoding instance passed" do
      @s.rb_to_encoding(Encoding::BINARY).should == "ASCII-8BIT"
    end

    it "returns the correct encoding for a replicated encoding" do
      @s.rb_to_encoding(Encoding::IBM857).should == "IBM857"
    end

    it "returns the encoding when passed a String" do
      @s.rb_to_encoding("ASCII").should == "US-ASCII"
    end

    it "calls #to_str to convert the argument to a String" do
      obj = mock("rb_to_encoding Encoding name")
      obj.should_receive(:to_str).and_return("utf-8")

      @s.rb_to_encoding(obj).should == "UTF-8"
    end

    describe "when the rb_encoding struct is stored in native memory" do
      it "can still read the name of the encoding" do
        address = @s.rb_to_encoding_native_store(Encoding::UTF_8)
        address.should be_kind_of(Integer)
        @s.rb_to_encoding_native_name(address).should == "UTF-8"
      end
    end
  end

  describe "rb_to_encoding_index" do
    it "returns the index of the encoding for the Encoding instance passed" do
      @s.rb_to_encoding_index(Encoding::BINARY).should >= 0
    end

    it "returns the index of the encoding when passed a String" do
      @s.rb_to_encoding_index("ASCII").should >= 0
    end

    it "returns the index of the dummy encoding of an Object" do
      index = Encoding.list.index(Encoding::UTF_16)
      @s.rb_to_encoding_index(Encoding::UTF_16.name).should == index
    end

    it "calls #to_str to convert the argument to a String" do
      obj = mock("rb_to_encoding Encoding name")
      obj.should_receive(:to_str).and_return("utf-8")

      @s.rb_to_encoding_index(obj).should >= 0
    end
  end

  describe "rb_enc_compatible" do
    it "returns 0 if the encodings of the Strings are not compatible" do
      a = [0xff].pack('C').force_encoding "binary"
      b = "\u3042".encode("utf-8")
      @s.rb_enc_compatible(a, b).should == 0
    end

    # The coverage of this sucks, but there is not a simple way (yet?) to
    # easily share the specs between rb_enc_compatible and
    # Encoding.compatible?
    it "returns the same value as Encoding.compatible? if the Strings have a compatible encoding" do
      a = "abc".force_encoding("us-ascii")
      b = "\u3042".encode("utf-8")
      @s.rb_enc_compatible(a, b).should == Encoding.compatible?(a, b)
    end
  end

  describe "rb_enc_copy" do
    before :each do
      @obj = "rb_enc_copy".encode(Encoding::US_ASCII)
    end

    it "sets the encoding of a String to that of the second argument" do
      @s.rb_enc_copy("string", @obj).encoding.should == Encoding::US_ASCII
    end

    it "raises a RuntimeError if the second argument is a Symbol" do
      -> { @s.rb_enc_copy(:symbol, @obj) }.should raise_error(RuntimeError)
    end

    it "sets the encoding of a Regexp to that of the second argument" do
      @s.rb_enc_copy(/regexp/.dup, @obj).encoding.should == Encoding::US_ASCII
    end
  end

  describe "rb_default_internal_encoding" do
    before :each do
      @default = Encoding.default_internal
    end

    after :each do
      Encoding.default_internal = @default
    end

    it "returns 0 if Encoding.default_internal is nil" do
      Encoding.default_internal = nil
      @s.rb_default_internal_encoding.should be_nil
    end

    it "returns the encoding for Encoding.default_internal" do
      Encoding.default_internal = "US-ASCII"
      @s.rb_default_internal_encoding.should == "US-ASCII"
      Encoding.default_internal = "UTF-8"
      @s.rb_default_internal_encoding.should == "UTF-8"
    end
  end

  describe "rb_default_external_encoding" do
    before :each do
      @default = Encoding.default_external
    end

    after :each do
      Encoding.default_external = @default
    end

    it "returns the encoding for Encoding.default_external" do
      Encoding.default_external = "ASCII-8BIT"
      @s.rb_default_external_encoding.should == "ASCII-8BIT"
    end
  end

  describe "rb_enc_associate" do
    it "sets the encoding of a String to the encoding" do
      @s.rb_enc_associate("string", "BINARY").encoding.should == Encoding::BINARY
    end

    it "raises a RuntimeError if the argument is Symbol" do
      -> { @s.rb_enc_associate(:symbol, "US-ASCII") }.should raise_error(RuntimeError)
    end

    it "sets the encoding of a Regexp to the encoding" do
      @s.rb_enc_associate(/regexp/.dup, "BINARY").encoding.should == Encoding::BINARY
    end

    it "sets the encoding of a String to a default when the encoding is NULL" do
      @s.rb_enc_associate("string", nil).encoding.should == Encoding::BINARY
    end
  end

  describe "rb_enc_associate_index" do
    it "sets the encoding of a String to the encoding" do
      index = @s.rb_enc_find_index("BINARY")
      enc = @s.rb_enc_associate_index("string", index).encoding
      enc.should == Encoding::BINARY
    end

    it "sets the encoding of a Regexp to the encoding" do
      index = @s.rb_enc_find_index("UTF-8")
      enc = @s.rb_enc_associate_index(/regexp/.dup, index).encoding
      enc.should == Encoding::UTF_8
    end

    it "sets the encoding of a Symbol to the encoding" do
      index = @s.rb_enc_find_index("UTF-8")
      -> { @s.rb_enc_associate_index(:symbol, index) }.should raise_error(RuntimeError)
    end
  end

  describe "rb_ascii8bit_encindex" do
    it "returns an index for the ASCII-8BIT encoding" do
      @s.rb_ascii8bit_encindex().should >= 0
    end
  end

  describe "rb_utf8_encindex" do
    it "returns an index for the UTF-8 encoding" do
      @s.rb_utf8_encindex().should >= 0
    end
  end

  describe "rb_usascii_encindex" do
    it "returns an index for the US-ASCII encoding" do
      @s.rb_usascii_encindex().should >= 0
    end
  end

  describe "rb_locale_encindex" do
    it "returns an index for the locale encoding" do
      @s.rb_locale_encindex().should >= 0
    end
  end

  describe "rb_filesystem_encindex" do
    it "returns an index for the filesystem encoding" do
      @s.rb_filesystem_encindex().should >= 0
    end
  end

  describe "rb_enc_to_index" do
    it "returns an index for the encoding" do
      @s.rb_enc_to_index("UTF-8").should >= 0
    end

    it "returns a non-negative int if the encoding is not defined" do
      # Encoding indexes are an implementation detail and not guaranteed
      # across implementations.
      @s.rb_enc_to_index("FTU-81").should >= 0
    end
  end

  describe "rb_enc_nth" do
    it "returns the byte index of the given character index" do
      @s.rb_enc_nth("hüllo", 3).should == 4
    end
  end

  describe "rb_enc_codepoint_len" do
    it "raises ArgumentError if an empty string is given" do
      -> do
        @s.rb_enc_codepoint_len("")
      end.should raise_error(ArgumentError)
    end

    it "raises ArgumentError if an invalid byte sequence is given" do
      -> do
        @s.rb_enc_codepoint_len([0xa0, 0xa1].pack('CC').force_encoding('utf-8')) # Invalid sequence identifier
      end.should raise_error(ArgumentError)
    end

    it "returns codepoint 0x24 and length 1 for character '$'" do
      codepoint, length = @s.rb_enc_codepoint_len("$")

      codepoint.should == 0x24
      length.should == 1
    end

    it "returns codepoint 0xA2 and length 2 for character '¢'" do
      codepoint, length = @s.rb_enc_codepoint_len("¢")

      codepoint.should == 0xA2
      length.should == 2
    end

    it "returns codepoint 0x20AC and length 3 for character '€'" do
      codepoint, length = @s.rb_enc_codepoint_len("€")

      codepoint.should == 0x20AC
      length.should == 3
    end

    it "returns codepoint 0x24B62 and length 4 for character '𤭢'" do
      codepoint, length = @s.rb_enc_codepoint_len("𤭢")

      codepoint.should == 0x24B62
      length.should == 4
    end
  end

  describe "rb_enc_str_asciionly_p" do
    it "returns true for an ASCII string" do
      @s.rb_enc_str_asciionly_p("hello").should be_true
    end

    it "returns false for a non-ASCII string" do
      @s.rb_enc_str_asciionly_p("hüllo").should be_false
    end
  end

  describe "rb_uv_to_utf8" do
    it 'converts a Unicode codepoint to a UTF-8 C string' do
      str = ' ' * 6
      {
        1  => "\x01",
        0x80 => "\xC2\x80",
        0x800 => "\xE0\xA0\x80",
        0x10000 => "\xF0\x90\x80\x80",
        0x200000 => "\xF8\x88\x80\x80\x80",
        0x4000000 => "\xFC\x84\x80\x80\x80\x80",
      }.each do |num, result|
        len = @s.rb_uv_to_utf8(str, num)
        str.byteslice(0, len).should == result
      end
    end
  end

  describe "ONIGENC_MBC_CASE_FOLD" do
    it "returns the correct case fold for the given string" do
      @s.ONIGENC_MBC_CASE_FOLD("lower").should == ["l", 1]
      @s.ONIGENC_MBC_CASE_FOLD("Upper").should == ["u", 1]
      @s.ONIGENC_MBC_CASE_FOLD("ABC"[1..-1]).should == ["b", 1]
    end

    it "works with other encodings" do
      @s.ONIGENC_MBC_CASE_FOLD("lower".force_encoding("binary")).should == ["l", 1]
      @s.ONIGENC_MBC_CASE_FOLD("Upper".force_encoding("binary")).should == ["u", 1]
      @s.ONIGENC_MBC_CASE_FOLD("É").should == ["é", 2]

      str, length = @s.ONIGENC_MBC_CASE_FOLD('$'.encode(Encoding::UTF_16BE))
      length.should == 2
      str.bytes.should == [0, 0x24]
    end
  end
end
