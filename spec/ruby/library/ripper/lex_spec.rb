require_relative '../../spec_helper'
require 'ripper'

describe "Ripper.lex" do
  it "lexes a simple method declaration" do
    expected = [
        [[1, 0], :on_kw, "def", 'FNAME'],
        [[1, 3], :on_sp, " ", 'FNAME'],
        [[1, 4], :on_ident, "m", 'ENDFN'],
        [[1, 5], :on_lparen, "(", 'BEG|LABEL'],
        [[1, 6], :on_ident, "a", 'ARG'],
        [[1, 7], :on_rparen, ")", 'ENDFN'],
        [[1, 8], :on_sp, " ", 'BEG'],
        [[1, 9], :on_kw, "nil", 'END'],
        [[1, 12], :on_sp, " ", 'END'],
        [[1, 13], :on_kw, "end", 'END']
    ]
    lexed = Ripper.lex("def m(a) nil end")
    lexed.map { |e|
      e[0...-1] + [e[-1].to_s.split('|').map { |s| s.sub(/^EXPR_/, '') }.join('|')]
    }.should == expected
  end
end
