require_relative '../../spec_helper'

ruby_version_is ""..."4.0" do
  require 'cgi'
end
ruby_version_is "4.0" do
  require 'cgi/escape'
end

describe "CGI.unescapeURIComponent" do
  it "decodes any percent-encoded octets to their corresponding bytes according to RFC 3986" do
    string = (0x00..0xff).map { |i| "%%%02x" % i }.join
    expected = (0x00..0xff).map { |i| i.chr }.join.force_encoding(Encoding::UTF_8)
    CGI.unescapeURIComponent(string).should == expected
  end

  it "disregards case of characters in a percent-encoding triplet" do
    CGI.unescapeURIComponent("%CE%B2abc").should == "βabc"
    CGI.unescapeURIComponent("%ce%b2ABC").should == "βABC"
  end

  it "leaves any non-percent-encoded characters as-is" do
    string = "ABCDEFGHIJKLMNOPQRSTUVWXYZ:/?#[]@!$&'()*+,;=\t\x0D\xFFβᛉ▒90%"
    decoded = CGI.unescapeURIComponent(string)
    decoded.should == string
    string.should_not.equal?(decoded)
  end

  it "leaves sequences which can't be a percent-encoded octet as-is" do
    string = "%AZ%B"
    decoded = CGI.unescapeURIComponent(string)
    decoded.should == string
    string.should_not.equal?(decoded)
  end

  it "creates a String with the specified target Encoding" do
    string = CGI.unescapeURIComponent("%D2%3C%3CABC", Encoding::ISO_8859_1)
    string.encoding.should == Encoding::ISO_8859_1
    string.should == "Ò<<ABC".encode("ISO-8859-1")
  end

  it "accepts a string name of an Encoding" do
    CGI.unescapeURIComponent("%D2%3C%3CABC", "ISO-8859-1").should == "Ò<<ABC".encode("ISO-8859-1")
  end

  it "raises ArgumentError if specified encoding is unknown" do
    -> { CGI.unescapeURIComponent("ABC", "ISO-JOKE-1") }.should raise_error(ArgumentError, "unknown encoding name - ISO-JOKE-1")
  end

  ruby_version_is ""..."4.0" do
    it "uses CGI.accept_charset as the default target encoding" do
      original_charset = CGI.accept_charset
      CGI.accept_charset = "ISO-8859-1"
      decoded = CGI.unescapeURIComponent("%D2%3C%3CABC")
      decoded.should == "Ò<<ABC".encode("ISO-8859-1")
      decoded.encoding.should == Encoding::ISO_8859_1
    ensure
      CGI.accept_charset = original_charset
    end

    it "has CGI.accept_charset as UTF-8 by default" do
      decoded = CGI.unescapeURIComponent("%CE%B2ABC")
      decoded.should == "βABC"
      decoded.encoding.should == Encoding::UTF_8
    end
  end

  ruby_version_is "4.0" do
    # "cgi/escape" does not have methods to access @@accept_charset.
    # Full "cgi" gem provides them, allowing to possibly change it.
    it "uses CGI's @@accept_charset as the default target encoding" do
      original_charset = CGI.class_variable_get(:@@accept_charset)
      CGI.class_variable_set(:@@accept_charset, "ISO-8859-1")
      decoded = CGI.unescapeURIComponent("%D2%3C%3CABC")
      decoded.should == "Ò<<ABC".encode("ISO-8859-1")
      decoded.encoding.should == Encoding::ISO_8859_1
    ensure
      CGI.class_variable_set(:@@accept_charset, original_charset)
    end

    it "has CGI's @@accept_charset as UTF-8 by default" do
      decoded = CGI.unescapeURIComponent("%CE%B2ABC")
      decoded.should == "βABC"
      decoded.encoding.should == Encoding::UTF_8
    end
  end

  context "when source string specifies octets invalid in target encoding" do
    it "uses source string's encoding" do
      string = "%A2%A6%A3".encode(Encoding::SHIFT_JIS)
      decoded = CGI.unescapeURIComponent(string, Encoding::US_ASCII)
      decoded.encoding.should == Encoding::SHIFT_JIS
      decoded.should == "｢ｦ｣".encode(Encoding::SHIFT_JIS)
      decoded.valid_encoding?.should be_true
    end

    it "uses source string's encoding even if it's also invalid" do
      string = "%FF".encode(Encoding::US_ASCII)
      decoded = CGI.unescapeURIComponent(string, Encoding::SHIFT_JIS)
      decoded.encoding.should == Encoding::US_ASCII
      decoded.should == "\xFF".dup.force_encoding(Encoding::US_ASCII)
      decoded.valid_encoding?.should be_false
    end
  end

  it "decodes an empty string as an empty string with target encoding" do
    string = "".encode(Encoding::BINARY)
    decoded = CGI.unescapeURIComponent(string, "UTF-8")
    decoded.should == ""
    decoded.encoding.should == Encoding::UTF_8
    string.should_not.equal?(decoded)
  end

  it "raises a TypeError with nil" do
    -> {
      CGI.unescapeURIComponent(nil)
    }.should raise_error(TypeError, "no implicit conversion of nil into String")
  end

  it "uses implicit type conversion to String" do
    object = Object.new
    def object.to_str
      "a%20b"
    end

    CGI.unescapeURIComponent(object).should == "a b"
  end
end
