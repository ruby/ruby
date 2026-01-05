require_relative '../../spec_helper'
begin
  require 'cgi/escape'
rescue LoadError
  require 'cgi'
end

describe "CGI.escapeURIComponent" do
  it "percent-encodes characters reserved according to RFC 3986" do
    # https://www.rfc-editor.org/rfc/rfc3986#section-2.2
    string = ":/?#[]@!$&'()*+,;="
    CGI.escapeURIComponent(string).should == "%3A%2F%3F%23%5B%5D%40%21%24%26%27%28%29%2A%2B%2C%3B%3D"
  end

  it "does not percent-encode unreserved characters according to RFC 3986" do
    string = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    CGI.escapeURIComponent(string).should == "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
  end

  it "encodes % character as %25" do
    CGI.escapeURIComponent("%").should == "%25"
  end

  # Compare to .escape which uses "+".
  it "percent-encodes single whitespace" do
    CGI.escapeURIComponent(" ").should == "%20"
  end

  it "percent-encodes all non-reserved and non-unreserved ASCII characters" do
    special_set = ":/?#[]@!$&'()*+,;=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    all_other = (0x00..0x7F).filter_map { |i| i.chr unless special_set.include?(i.chr) }.join
    encoded = CGI.escapeURIComponent(all_other)
    encoded.should.match?(/\A(?:%[0-9A-F]{2}){#{all_other.length}}\z/)
  end

  it "percent-encodes non-ASCII bytes" do
    bytes = (0x80..0xFF).map(&:chr).join
    encoded = CGI.escapeURIComponent(bytes)
    encoded.should.match?(/\A(?:%[0-9A-F]{2}){#{bytes.length}}\z/)
  end

  it "processes multi-byte characters as separate bytes, percent-encoding each one" do
    CGI.escapeURIComponent("β").should == "%CE%B2" # "β" bytes representation is CE B2
  end

  it "produces a copy of an empty string" do
    string = "".encode(Encoding::BINARY)
    encoded = CGI.escapeURIComponent(string)
    encoded.should == ""
    encoded.encoding.should == Encoding::BINARY
    string.should_not.equal?(encoded)
  end

  it "preserves string's encoding" do
    string = "whatever".encode("ASCII-8BIT")
    CGI.escapeURIComponent(string).encoding.should == Encoding::ASCII_8BIT
  end

  it "processes even strings with invalid encoding, percent-encoding octets as-is" do
    string = "\xC0<<".dup.force_encoding("UTF-8")
    CGI.escapeURIComponent(string).should == "%C0%3C%3C"
  end

  it "raises a TypeError with nil" do
    -> {
      CGI.escapeURIComponent(nil)
    }.should raise_error(TypeError, "no implicit conversion of nil into String")
  end

  it "uses implicit type conversion to String" do
    object = Object.new
    def object.to_str
      "a b"
    end

    CGI.escapeURIComponent(object).should == "a%20b"
  end
end
