# -*- encoding: binary -*-
require_relative '../../spec_helper'
require_relative '../fixtures/classes'

# TODO: synchronize with spec/core/regexp/new_spec.rb -
#       escaping is also tested there
describe "Regexps with escape characters" do
  it "supports escape sequences" do
    /\t/.match("\t").to_a.should == ["\t"] # horizontal tab
    /\v/.match("\v").to_a.should == ["\v"] # vertical tab
    /\n/.match("\n").to_a.should == ["\n"] # newline
    /\r/.match("\r").to_a.should == ["\r"] # return
    /\f/.match("\f").to_a.should == ["\f"] # form feed
    /\a/.match("\a").to_a.should == ["\a"] # bell
    /\e/.match("\e").to_a.should == ["\e"] # escape

    # \nnn         octal char            (encoded byte value)
  end

  it "supports quoting meta-characters via escape sequence" do
    # parenthesis, etc
    /\(/.match("(").to_a.should == ["("]
    /\)/.match(")").to_a.should == [")"]
    /\[/.match("[").to_a.should == ["["]
    /\]/.match("]").to_a.should == ["]"]
    /\{/.match("{").to_a.should == ["{"]
    /\}/.match("}").to_a.should == ["}"]
    /\</.match("<").to_a.should == ["<"]
    /\>/.match(">").to_a.should == [">"]
    # alternation separator
    /\|/.match("|").to_a.should == ["|"]
    # quantifiers
    /\?/.match("?").to_a.should == ["?"]
    /\./.match(".").to_a.should == ["."]
    /\*/.match("*").to_a.should == ["*"]
    /\+/.match("+").to_a.should == ["+"]
    # line anchors
    /\^/.match("^").to_a.should == ["^"]
    /\$/.match("$").to_a.should == ["$"]
  end

  it "supports quoting meta-characters via escape sequence when used as a terminator" do
    # parenthesis, etc
    # %r[[, %r((, etc literals - are forbidden
    %r(\().match("(").to_a.should == ["("]
    %r(\)).match(")").to_a.should == [")"]
    %r)\().match("(").to_a.should == ["("]
    %r)\)).match(")").to_a.should == [")"]

    %r[\[].match("[").to_a.should == ["["]
    %r[\]].match("]").to_a.should == ["]"]
    %r]\[].match("[").to_a.should == ["["]
    %r]\]].match("]").to_a.should == ["]"]

    %r{\{}.match("{").to_a.should == ["{"]
    %r{\}}.match("}").to_a.should == ["}"]
    %r}\{}.match("{").to_a.should == ["{"]
    %r}\}}.match("}").to_a.should == ["}"]

    %r<\<>.match("<").to_a.should == ["<"]
    %r<\>>.match(">").to_a.should == [">"]
    %r>\<>.match("<").to_a.should == ["<"]
    %r>\>>.match(">").to_a.should == [">"]

    # alternation separator
    %r|\||.match("|").to_a.should == ["|"]
    # quantifiers
    %r?\??.match("?").to_a.should == ["?"]
    %r.\...match(".").to_a.should == ["."]
    %r*\**.match("*").to_a.should == ["*"]
    %r+\++.match("+").to_a.should == ["+"]
    # line anchors
    %r^\^^.match("^").to_a.should == ["^"]
    %r$\$$.match("$").to_a.should == ["$"]
  end

  it "supports quoting non-meta-characters via escape sequence when used as a terminator" do
    non_meta_character_terminators = [
      '!', '"', '#', '%', '&', "'", ',', '-', ':', ';', '@', '_', '`', '/', '=', '~'
    ]

    non_meta_character_terminators.each do |c|
      pattern = eval("%r" + c + "\\" + c + c)
      pattern.match(c).to_a.should == [c]
    end
  end

  it "does not change semantics of escaped non-meta-character when used as a terminator" do
    all_terminators = [*("!".."/"), *(":".."@"), *("[".."`"), *("{".."~")]
    meta_character_terminators = ["$", "^", "*", "+", ".", "?", "|", "}", ")", ">", "]"]
    special_cases = ['(', '{', '[', '<', '\\']

    # it should be equivalent to
    #   [ '!', '"', '#', '%', '&', "'", ',', '-', ':', ';', '@', '_', '`', '/', '=', '~' ]
    non_meta_character_terminators = all_terminators - meta_character_terminators - special_cases

    non_meta_character_terminators.each do |c|
      pattern = eval("%r" + c + "\\" + c + c)
      pattern.should == /#{c}/
    end
  end

  it "does not change semantics of escaped meta-character when used as a terminator" do
    meta_character_terminators = ["$", "^", "*", "+", ".", "?", "|", "}", ")", ">", "]"]

    meta_character_terminators.each do |c|
      pattern = eval("%r" + c + "\\" + c + c)
      pattern.should == eval("/\\#{c}/")
    end
  end

  it "allows any character to be escaped" do
    /\y/.match("y").to_a.should == ["y"]
  end

  it "supports \\x (hex characters)" do
    /\xA/.match("\nxyz").to_a.should == ["\n"]
    /\x0A/.match("\n").to_a.should == ["\n"]
    /\xAA/.match("\nA").should be_nil
    /\x0AA/.match("\nA").to_a.should == ["\nA"]
    /\xAG/.match("\nG").to_a.should == ["\nG"]
    # Non-matches
    -> { eval('/\xG/') }.should raise_error(SyntaxError)

    # \x{7HHHHHHH} wide hexadecimal char (character code point value)
  end

  it "supports \\c (control characters)" do
    #/\c \c@\c`/.match("\00\00\00").to_a.should == ["\00\00\00"]
    /\c#\cc\cC/.match("\03\03\03").to_a.should == ["\03\03\03"]
    /\c'\cG\cg/.match("\a\a\a").to_a.should == ["\a\a\a"]
    /\c(\cH\ch/.match("\b\b\b").to_a.should == ["\b\b\b"]
    /\c)\cI\ci/.match("\t\t\t").to_a.should == ["\t\t\t"]
    /\c*\cJ\cj/.match("\n\n\n").to_a.should == ["\n\n\n"]
    /\c+\cK\ck/.match("\v\v\v").to_a.should == ["\v\v\v"]
    /\c,\cL\cl/.match("\f\f\f").to_a.should == ["\f\f\f"]
    /\c-\cM\cm/.match("\r\r\r").to_a.should == ["\r\r\r"]

    /\cJ/.match("\r").should be_nil

    # Parsing precedence
    /\cJ+/.match("\n\n").to_a.should == ["\n\n"] # Quantifiers apply to entire escape sequence
    /\\cJ/.match("\\cJ").to_a.should == ["\\cJ"]
    -> { eval('/[abc\x]/') }.should raise_error(SyntaxError) # \x is treated as a escape sequence even inside a character class
    # Syntax error
    -> { eval('/\c/') }.should raise_error(SyntaxError)

    # \cx          control char          (character code point value)
    # \C-x         control char          (character code point value)
    # \M-x         meta  (x|0x80)        (character code point value)
    # \M-\C-x      meta control char     (character code point value)
  end

  it "handles three digit octal escapes starting with 0" do
    /[\000-\b]/.match("\x00")[0].should == "\x00"
  end

  it "handles control escapes with \\C-x syntax" do
    /\C-*\C-J\C-j/.match("\n\n\n")[0].should == "\n\n\n"
  end

  it "supports the \\K keep operator" do
    /a\Kb/.match("ab")[0].should == "b"
  end

  it "supports the \\R line break escape" do
    /\R/.match("\n")[0].should == "\n"
  end
end
