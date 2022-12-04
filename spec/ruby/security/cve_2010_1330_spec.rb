require_relative '../spec_helper'

describe "String#gsub" do
  it "resists CVE-2010-1330 by raising an exception on invalid UTF-8 bytes" do
    # This original vulnerability talked about KCODE, which is no longer
    # used. Instead we are forcing encodings here. But I think the idea is the
    # same - we want to check that Ruby implementations raise an error on
    # #gsub on a string in the UTF-8 encoding but with invalid an UTF-8 byte
    # sequence.

    str = "\xF6<script>"
    str.force_encoding Encoding::BINARY
    str.gsub(/</, "&lt;").should == "\xF6&lt;script>".b
    str.force_encoding Encoding::UTF_8
    -> {
      str.gsub(/</, "&lt;")
    }.should raise_error(ArgumentError, /invalid byte sequence in UTF-8/)
  end
end
