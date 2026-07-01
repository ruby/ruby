require_relative '../../spec_helper'

describe "String#to_sym" do
  it "returns the symbol corresponding to self" do
    "Koala".to_sym.should.equal? :Koala
    'cat'.to_sym.should.equal? :cat
    '@cat'.to_sym.should.equal? :@cat
    'cat and dog'.to_sym.should.equal? :"cat and dog"
    "abc=".to_sym.should.equal? :abc=
  end

  it "does not special case +(binary) and -(binary)" do
    "+(binary)".to_sym.should.equal? :"+(binary)"
    "-(binary)".to_sym.should.equal? :"-(binary)"
  end

  it "does not special case certain operators" do
    "!@".to_sym.should.equal? :"!@"
    "~@".to_sym.should.equal? :"~@"
    "!(unary)".to_sym.should.equal? :"!(unary)"
    "~(unary)".to_sym.should.equal? :"~(unary)"
    "+(unary)".to_sym.should.equal? :"+(unary)"
    "-(unary)".to_sym.should.equal? :"-(unary)"
  end

  it "returns a US-ASCII Symbol for a UTF-8 String containing only US-ASCII characters" do
    sym = "foobar".to_sym
    sym.encoding.should == Encoding::US_ASCII
    sym.should.equal? :"foobar"
  end

  it "returns a US-ASCII Symbol for a binary String containing only US-ASCII characters" do
    sym = "foobar".b.to_sym
    sym.encoding.should == Encoding::US_ASCII
    sym.should.equal? :"foobar"
  end

  it "returns a UTF-8 Symbol for a UTF-8 String containing non US-ASCII characters" do
    sym = "il était une fois".to_sym
    sym.encoding.should == Encoding::UTF_8
    sym.should.equal? :"il était une fois"
  end

  it "returns a UTF-16LE Symbol for a UTF-16LE String containing non US-ASCII characters" do
    utf16_str = "UtéF16".encode(Encoding::UTF_16LE)
    sym = utf16_str.to_sym
    sym.encoding.should == Encoding::UTF_16LE
    sym.to_s.should == utf16_str
  end

  it "returns a binary Symbol for a binary String containing non US-ASCII characters" do
    binary_string = "binarí".b
    sym = binary_string.to_sym
    sym.encoding.should == Encoding::BINARY
    sym.to_s.should == binary_string
  end

  it "ignores existing symbols with different encoding" do
    source = "fée"

    iso_symbol = source.dup.force_encoding(Encoding::ISO_8859_1).to_sym
    iso_symbol.encoding.should == Encoding::ISO_8859_1
    binary_symbol = source.dup.force_encoding(Encoding::BINARY).to_sym
    binary_symbol.encoding.should == Encoding::BINARY
  end

  it "raises an EncodingError for UTF-8 String containing invalid bytes" do
    invalid_utf8 = "\xC3"
    invalid_utf8.should_not.valid_encoding?
    -> {
      invalid_utf8.to_sym
    }.should.raise(EncodingError, 'invalid symbol in encoding UTF-8 :"\xC3"')
  end
end
