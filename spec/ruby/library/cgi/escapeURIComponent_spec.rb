require_relative '../../spec_helper'
require 'cgi'

describe "CGI.escapeURIComponent" do
  it "escapes whitespace" do
    string = "&<>\" \xE3\x82\x86\xE3\x82\x93\xE3\x82\x86\xE3\x82\x93"
    CGI.escapeURIComponent(string).should == '%26%3C%3E%22%20%E3%82%86%E3%82%93%E3%82%86%E3%82%93'
  end

  it "does not escape with unreserved characters" do
    string = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    CGI.escapeURIComponent(string).should == "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
  end

  it "supports String with invalid encoding" do
    string = "\xC0\<\<".dup.force_encoding("UTF-8")
    CGI.escapeURIComponent(string).should == "%C0%3C%3C"
  end

  it "processes String bytes one by one, not characters" do
    CGI.escapeURIComponent("β").should == "%CE%B2" # "β" bytes representation is CE B2
  end

  it "raises a TypeError with nil" do
    -> {
      CGI.escapeURIComponent(nil)
    }.should raise_error(TypeError, 'no implicit conversion of nil into String')
  end

  it "encodes empty string" do
    CGI.escapeURIComponent("").should == ""
  end

  it "encodes single whitespace" do
    CGI.escapeURIComponent(" ").should == "%20"
  end

  it "encodes double whitespace" do
    CGI.escapeURIComponent("  ").should == "%20%20"
  end

  it "preserves encoding" do
    string = "whatever".encode("ASCII-8BIT")
    CGI.escapeURIComponent(string).encoding.should == Encoding::ASCII_8BIT
  end

  it "uses implicit type conversion to String" do
    object = Object.new
    def object.to_str
      "a b"
    end

    CGI.escapeURIComponent(object).should == "a%20b"
  end
end
