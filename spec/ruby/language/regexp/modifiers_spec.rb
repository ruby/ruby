require_relative '../../spec_helper'
require_relative '../fixtures/classes'

describe "Regexps with modifiers" do
  it "supports /i (case-insensitive)" do
    /foo/i.match("FOO").to_a.should == ["FOO"]
  end

  it "supports /m (multiline)" do
    /foo.bar/m.match("foo\nbar").to_a.should == ["foo\nbar"]
    /foo.bar/.match("foo\nbar").should == nil
  end

  it "supports /x (extended syntax)" do
    /\d +/x.match("abc123").to_a.should == ["123"] # Quantifiers can be separated from the expression they apply to
  end

  it "supports /o (once)" do
    2.times do |i|
      /#{i}/o.should == /0/
    end
  end

  it "invokes substitutions for /o only once" do
    ScratchPad.record []
    o = Object.new
    def o.to_s
      ScratchPad << :to_s
      "class_with_to_s"
    end
    eval "2.times { /#{o}/o }"
    ScratchPad.recorded.should == [:to_s]
  end

  it "supports modifier combinations" do
    /foo/imox.match("foo").to_a.should == ["foo"]
    /foo/imoximox.match("foo").to_a.should == ["foo"]

    -> { eval('/foo/a') }.should.raise(SyntaxError)
  end

  it "supports (?~) (absent operator)" do
    Regexp.new("(?~foo)").match("hello").to_a.should == ["hello"]
    "foo".scan(Regexp.new("(?~foo)")).should == ["fo","o",""]
  end

  it "supports (?imx-imx) (inline modifiers)" do
    /(?i)foo/.match("FOO").to_a.should == ["FOO"]
    /foo(?i)/.match("FOO").should == nil
    # Interaction with /i
    /(?-i)foo/i.match("FOO").should == nil
    /foo(?-i)/i.match("FOO").to_a.should == ["FOO"]
    # Multiple uses
    /foo (?i)bar (?-i)baz/.match("foo BAR baz").to_a.should == ["foo BAR baz"]
    /foo (?i)bar (?-i)baz/.match("foo BAR BAZ").should == nil

    /(?m)./.match("\n").to_a.should == ["\n"]
    /.(?m)/.match("\n").should == nil
    # Interaction with /m
    /(?-m)./m.match("\n").should == nil
    /.(?-m)/m.match("\n").to_a.should == ["\n"]
    # Multiple uses
    /. (?m). (?-m)./.match(". \n .").to_a.should == [". \n ."]
    /. (?m). (?-m)./.match(". \n \n").should == nil

    /(?x) foo /.match("foo").to_a.should == ["foo"]
    / foo (?x)/.match("foo").should == nil
    # Interaction with /x
    /(?-x) foo /x.match("foo").should == nil
    / foo (?-x)/x.match("foo").to_a.should == ["foo"]
    # Multiple uses
    /( foo )(?x)( bar )(?-x)( baz )/.match(" foo bar baz ").to_a.should == [" foo bar baz ", " foo ", "bar", " baz "]
    /( foo )(?x)( bar )(?-x)( baz )/.match(" foo barbaz").should == nil

    # Parsing
    /(?i-i)foo/.match("FOO").should == nil
    /(?ii)foo/.match("FOO").to_a.should == ["FOO"]
    /(?-)foo/.match("foo").to_a.should == ["foo"]
    -> { eval('/(?o)/') }.should.raise(SyntaxError)
  end

  it "supports (?imx-imx:expr) (scoped inline modifiers)" do
    /foo (?i:bar) baz/.match("foo BAR baz").to_a.should == ["foo BAR baz"]
    /foo (?i:bar) baz/.match("foo BAR BAZ").should == nil
    /foo (?-i:bar) baz/i.match("foo BAR BAZ").should == nil

    /. (?m:.) ./.match(". \n .").to_a.should == [". \n ."]
    /. (?m:.) ./.match(". \n \n").should == nil
    /. (?-m:.) ./m.match("\n \n \n").should == nil

    /( foo )(?x: bar )( baz )/.match(" foo bar baz ").to_a.should == [" foo bar baz ", " foo ", " baz "]
    /( foo )(?x: bar )( baz )/.match(" foo barbaz").should == nil
    /( foo )(?-x: bar )( baz )/x.match("foo bar baz").to_a.should == ["foo bar baz", "foo", "baz"]

    # Parsing
    /(?i-i:foo)/.match("FOO").should == nil
    /(?ii:foo)/.match("FOO").to_a.should == ["FOO"]
    /(?-:)foo/.match("foo").to_a.should == ["foo"]
    -> { eval('/(?o:)/') }.should.raise(SyntaxError)
  end

  it "supports . with /m" do
    # Basic matching
    /./m.match("\n").to_a.should == ["\n"]
  end

  it "supports ASCII/Unicode modifiers" do
    eval('/(?a)[[:alpha:]]+/').match("a\u3042").to_a.should == ["a"]
    eval('/(?d)[[:alpha:]]+/').match("a\u3042").to_a.should == ["a\u3042"]
    eval('/(?u)[[:alpha:]]+/').match("a\u3042").to_a.should == ["a\u3042"]
    eval('/(?a)\w+/').match("a\u3042").to_a.should == ["a"]
    eval('/(?d)\w+/').match("a\u3042").to_a.should == ["a"]
    eval('/(?u)\w+/').match("a\u3042").to_a.should == ["a\u3042"]
  end
end
