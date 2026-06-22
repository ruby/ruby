require_relative '../../spec_helper'

describe "Symbol#inspect" do
  symbols = {
    fred:         ":fred",
    :fred?     => ":fred?",
    :fred!     => ":fred!",
    :BAD!      => ":BAD!",
    :_BAD!     => ":_BAD!",
    :$ruby     => ":$ruby",
    :@ruby     => ":@ruby",
    :@@ruby    => ":@@ruby",
    :"$ruby!"  => ":\"$ruby!\"",
    :"$ruby?"  => ":\"$ruby?\"",
    :"@ruby!"  => ":\"@ruby!\"",
    :"@ruby?"  => ":\"@ruby?\"",
    :"@@ruby!" => ":\"@@ruby!\"",
    :"@@ruby?" => ":\"@@ruby?\"",

    :$-w       => ":$-w",
    :"$-ww"    => ":\"$-ww\"",
    :"$+"      => ":$+",
    :"$~"      => ":$~",
    :"$:"      => ":$:",
    :"$?"      => ":$?",
    :"$<"      => ":$<",
    :"$_"      => ":$_",
    :"$/"      => ":$/",
    :"$'"      => ":$'",
    :"$\""     => ":$\"",
    :"$$"      => ":$$",
    :"$."      => ":$.",
    :"$,"      => ":$,",
    :"$`"      => ":$`",
    :"$!"      => ":$!",
    :"$;"      => ":$;",
    :"$\\"     => ":$\\",
    :"$="      => ":$=",
    :"$*"      => ":$*",
    :"$>"      => ":$>",
    :"$&"      => ":$&",
    :"$@"      => ":$@",
    :"$1234"   => ":$1234",

    :-@        => ":-@",
    :+@        => ":+@",
    :%         => ":%",
    :&         => ":&",
    :*         => ":*",
    :**        => ":**",
    :"/"       => ":/",     # lhs quoted for emacs happiness
    :<         => ":<",
    :<=        => ":<=",
    :<=>       => ":<=>",
    :==        => ":==",
    :===       => ":===",
    :=~        => ":=~",
    :>         => ":>",
    :>=        => ":>=",
    :>>        => ":>>",
    :[]        => ":[]",
    :[]=       => ":[]=",
    :"\<\<"    => ":\<\<",
    :^         => ":^",
    :"`"       => ":`",     # for emacs, and justice!
    :~         => ":~",
    :|         => ":|",

    :"!"       => ":!",
    :"!="      => ":!=",
    :"!~"      => ":!~",
    :"\$"      => ":\"$\"", # for justice!
    :"&&"      => ":\"&&\"",
    :"'"       => ":\"\'\"",
    :","       => ":\",\"",
    :"."       => ":\".\"",
    :".."      => ":\"..\"",
    :"..."     => ":\"...\"",
    :":"       => ":\":\"",
    :"::"      => ":\"::\"",
    :";"       => ":\";\"",
    :"="       => ":\"=\"",
    :"=>"      => ":\"=>\"",
    :"\?"      => ":\"?\"", # rawr!
    :"@"       => ":\"@\"",
    :"||"      => ":\"||\"",
    :"|||"     => ":\"|||\"",
    :"++"      => ":\"++\"",

    :"\""      => ":\"\\\"\"",
    :"\"\""    => ":\"\\\"\\\"\"",

    :"9"       => ":\"9\"",
    :"foo bar" => ":\"foo bar\"",
    :"*foo"    => ":\"*foo\"",
    :"foo "    => ":\"foo \"",
    :" foo"    => ":\" foo\"",
    :" "       => ":\" \"",

    :"ê"       => [":ê", ":\"\\u00EA\""],
    :"测"      => [":测", ":\"\\u6D4B\""],
    :"🦊"      => [":🦊", ":\"\\u{1F98A}\""],
  }

  expected_by_encoding = Encoding::default_external == Encoding::UTF_8 ? 0 : 1
  symbols.each do |input, expected|
    expected = expected[expected_by_encoding] if expected.is_a?(Array)
    it "returns self as a symbol literal for #{expected}" do
      input.inspect.should == expected
    end
  end

  it "quotes BINARY symbols" do
    sym = "foo\xA4".b.to_sym
    sym.inspect.should == ':"foo\xA4"'
  end

  it "quotes symbols in non-ASCII-compatible encodings" do
    Encoding.list.reject(&:ascii_compatible?).reject(&:dummy?).each do |encoding|
      sym = "foo".encode(encoding).to_sym
      sym.inspect.should == ':"foo"'
    end
  end

  it "quotes and escapes symbols in dummy encodings" do
    Encoding.list.select(&:dummy?).each do |encoding|
      sym = "abcd".dup.force_encoding(encoding).to_sym
      sym.inspect.should == ':"\x61\x62\x63\x64"'
    end
  end
end
