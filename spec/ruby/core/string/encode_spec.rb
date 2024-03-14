# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'shared/encode'

describe "String#encode" do
  before :each do
    @external = Encoding.default_external
    @internal = Encoding.default_internal
  end

  after :each do
    Encoding.default_external = @external
    Encoding.default_internal = @internal
  end

  it_behaves_like :string_encode, :encode

  describe "when passed no options" do
    it "returns a copy when Encoding.default_internal is nil" do
      Encoding.default_internal = nil
      str = "あ"
      encoded = str.encode
      encoded.should_not equal(str)
      encoded.should == str
    end

    it "returns a copy for a ASCII-only String when Encoding.default_internal is nil" do
      Encoding.default_internal = nil
      str = "abc"
      encoded = str.encode
      encoded.should_not equal(str)
      encoded.should == str
    end

    it "encodes an ascii substring of a binary string to UTF-8" do
      x82 = [0x82].pack('C')
      str =  "#{x82}foo".dup.force_encoding("binary")[1..-1].encode("utf-8")
      str.should == "foo".dup.force_encoding("utf-8")
      str.encoding.should equal(Encoding::UTF_8)
    end
  end

  describe "when passed to encoding" do
    it "returns a copy when passed the same encoding as the String" do
      str = "あ"
      encoded = str.encode(Encoding::UTF_8)
      encoded.should_not equal(str)
      encoded.should == str
    end

    it "round trips a String" do
      str = "abc def".dup.force_encoding Encoding::US_ASCII
      str.encode("utf-32be").encode("ascii").should == "abc def"
    end
  end

  describe "when passed options" do
    it "returns a copy when Encoding.default_internal is nil" do
      Encoding.default_internal = nil
      str = "あ"
      str.encode(invalid: :replace).should_not equal(str)
    end

    it "normalizes newlines" do
      "\r\nfoo".encode(universal_newline: true).should == "\nfoo"

      "\rfoo".encode(universal_newline: true).should == "\nfoo"
    end

    it "replaces invalid encoding in source with default replacement" do
      encoded = "ち\xE3\x81\xFF".encode("UTF-16LE", invalid: :replace)
      encoded.should == "\u3061\ufffd\ufffd".encode("UTF-16LE")
      encoded.encode("UTF-8").should == "ち\ufffd\ufffd"
    end

    it "replaces invalid encoding in source with a specified replacement" do
      encoded = "ち\xE3\x81\xFF".encode("UTF-16LE", invalid: :replace, replace: "foo")
      encoded.should == "\u3061foofoo".encode("UTF-16LE")
      encoded.encode("UTF-8").should == "ちfoofoo"
    end

    it "replace multiple invalid bytes at the end with a single replacement character" do
      "\xE3\x81\x93\xE3\x81".encode("UTF-8", invalid: :replace).should == "\u3053\ufffd"
    end

    it "replaces invalid encoding in source using a specified replacement even when a fallback is given" do
      encoded = "ち\xE3\x81\xFF".encode("UTF-16LE", invalid: :replace, replace: "foo", fallback: -> c { "bar" })
      encoded.should == "\u3061foofoo".encode("UTF-16LE")
      encoded.encode("UTF-8").should == "ちfoofoo"
    end

    it "replaces undefined encoding in destination with default replacement" do
      encoded = "B\ufffd".encode(Encoding::US_ASCII, undef: :replace)
      encoded.should == "B?".encode(Encoding::US_ASCII)
      encoded.encode("UTF-8").should == "B?"
    end

    it "replaces undefined encoding in destination with a specified replacement" do
      encoded = "B\ufffd".encode(Encoding::US_ASCII, undef: :replace, replace: "foo")
      encoded.should == "Bfoo".encode(Encoding::US_ASCII)
      encoded.encode("UTF-8").should == "Bfoo"
    end

    it "replaces undefined encoding in destination with a specified replacement even if a fallback is given" do
      encoded = "B\ufffd".encode(Encoding::US_ASCII, undef: :replace, replace: "foo", fallback: proc {|x| "bar"})
      encoded.should == "Bfoo".encode(Encoding::US_ASCII)
      encoded.encode("UTF-8").should == "Bfoo"
    end

    it "replaces undefined encoding in destination using a fallback proc" do
      encoded = "B\ufffd".encode(Encoding::US_ASCII, fallback: proc {|x| "bar"})
      encoded.should == "Bbar".encode(Encoding::US_ASCII)
      encoded.encode("UTF-8").should == "Bbar"
    end

    it "replaces invalid encoding in source using replace even when fallback is given as proc" do
      encoded = "ち\xE3\x81\xFF".encode("UTF-16LE", invalid: :replace, replace: "foo", fallback: proc {|x| "bar"})
      encoded.should == "\u3061foofoo".encode("UTF-16LE")
      encoded.encode("UTF-8").should == "ちfoofoo"
    end
  end

  describe "when passed to, from" do
    it "returns a copy in the destination encoding when both encodings are the same" do
      str = "あ".dup.force_encoding("binary")
      encoded = str.encode("utf-8", "utf-8")

      encoded.should_not equal(str)
      encoded.should == str.force_encoding("utf-8")
      encoded.encoding.should == Encoding::UTF_8
    end

    it "returns the transcoded string" do
      str = "\x00\x00\x00\x1F"
      str.encode(Encoding::UTF_8, Encoding::UTF_16BE).should == "\u0000\u001f"
    end
  end

  describe "when passed to, options" do
    it "returns a copy when the destination encoding is the same as the String encoding" do
      str = "あ"
      encoded = str.encode(Encoding::UTF_8, undef: :replace)
      encoded.should_not equal(str)
      encoded.should == str
    end
  end

  describe "when passed to, from, options" do
    it "returns a copy when both encodings are the same" do
      str = "あ"
      encoded = str.encode("utf-8", "utf-8", invalid: :replace)
      encoded.should_not equal(str)
      encoded.should == str
    end

    it "returns a copy in the destination encoding when both encodings are the same" do
      str = "あ".dup.force_encoding("binary")
      encoded = str.encode("utf-8", "utf-8", invalid: :replace)

      encoded.should_not equal(str)
      encoded.should == str.force_encoding("utf-8")
      encoded.encoding.should == Encoding::UTF_8
    end
  end
end

describe "String#encode!" do
  before :each do
    @external = Encoding.default_external
    @internal = Encoding.default_internal
  end

  after :each do
    Encoding.default_external = @external
    Encoding.default_internal = @internal
  end

  it_behaves_like :string_encode, :encode!

  it "raises a FrozenError when called on a frozen String" do
    -> { "foo".freeze.encode!("euc-jp") }.should raise_error(FrozenError)
  end

  # http://redmine.ruby-lang.org/issues/show/1836
  it "raises a FrozenError when called on a frozen String when it's a no-op" do
    -> { "foo".freeze.encode!("utf-8") }.should raise_error(FrozenError)
  end

  describe "when passed no options" do
    it "returns self when Encoding.default_internal is nil" do
      Encoding.default_internal = nil
      str = +"あ"
      str.encode!.should equal(str)
    end

    it "returns self for a ASCII-only String when Encoding.default_internal is nil" do
      Encoding.default_internal = nil
      str = +"abc"
      str.encode!.should equal(str)
    end
  end

  describe "when passed options" do
    it "returns self for ASCII-only String when Encoding.default_internal is nil" do
      Encoding.default_internal = nil
      str = +"abc"
      str.encode!(invalid: :replace).should equal(str)
    end
  end

  describe "when passed to encoding" do
    it "returns self" do
      str = +"abc"
      result = str.encode!(Encoding::BINARY)
      result.encoding.should equal(Encoding::BINARY)
      result.should equal(str)
    end
  end

  describe "when passed to, from" do
    it "returns self" do
      str = +"ああ"
      result = str.encode!("euc-jp", "utf-8")
      result.encoding.should equal(Encoding::EUC_JP)
      result.should equal(str)
    end
  end
end
