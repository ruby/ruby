require 'stringio'
require_relative '../../spec_helper'

describe "StringIO#external_encoding" do
  it "gets the encoding of the underlying String" do
    io = StringIO.new
    io.set_encoding Encoding::EUC_JP
    io.external_encoding.should == Encoding::EUC_JP
  end

  it "changes to match string if string's encoding is changed" do
    io = StringIO.new
    io.string.force_encoding(Encoding::EUC_JP)
    io.external_encoding.should == Encoding::EUC_JP
  end

  it "does not set the encoding of its buffer string if the string is frozen" do
    str = "foo".freeze
    enc = str.encoding
    io = StringIO.new(str)
    io.set_encoding Encoding::EUC_JP
    io.external_encoding.should == Encoding::EUC_JP
    str.encoding.should == enc
  end
end
