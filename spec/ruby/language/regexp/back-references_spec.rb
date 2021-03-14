require_relative '../../spec_helper'
require_relative '../fixtures/classes'

describe "Regexps with back-references" do
  it "saves match data in the $~ pseudo-global variable" do
    "hello" =~ /l+/
    $~.to_a.should == ["ll"]
  end

  it "saves captures in numbered $[1-N] variables" do
    "1234567890" =~ /(1)(2)(3)(4)(5)(6)(7)(8)(9)(0)/
    $~.to_a.should == ["1234567890", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    $1.should == "1"
    $2.should == "2"
    $3.should == "3"
    $4.should == "4"
    $5.should == "5"
    $6.should == "6"
    $7.should == "7"
    $8.should == "8"
    $9.should == "9"
    $10.should == "0"
  end

  it "will not clobber capture variables across threads" do
    cap1, cap2, cap3 = nil
    "foo" =~ /(o+)/
    cap1 = [$~.to_a, $1]
    Thread.new do
      cap2 = [$~.to_a, $1]
      "bar" =~ /(a)/
      cap3 = [$~.to_a, $1]
    end.join
    cap4 = [$~.to_a, $1]
    cap1.should == [["oo", "oo"], "oo"]
    cap2.should == [[], nil]
    cap3.should == [["a", "a"], "a"]
    cap4.should == [["oo", "oo"], "oo"]
  end

  it "supports \<n> (backreference to previous group match)" do
    /(foo.)\1/.match("foo1foo1").to_a.should == ["foo1foo1", "foo1"]
    /(foo.)\1/.match("foo1foo2").should be_nil
  end

  it "resets nested \<n> backreference before match of outer subexpression" do
    /(a\1?){2}/.match("aaaa").to_a.should == ["aa", "a"]
  end

  it "does not reset enclosed capture groups" do
    /((a)|(b))+/.match("ab").captures.should == [ "b", "a", "b" ]
  end

  it "can match an optional quote, followed by content, followed by a matching quote, as the whole string" do
    /^("|)(.*)\1$/.match('x').to_a.should == ["x", "", "x"]
  end

  it "allows forward references" do
    /(?:(\2)|(.))+/.match("aa").to_a.should == [ "aa", "a", "a" ]
  end

  it "disallows forward references >= 10" do
    (/\10()()()()()()()()()()/ =~ "\x08").should == 0
  end

  it "fails when trying to match a backreference to an unmatched capture group" do
    /\1()/.match("").should == nil
    /(?:(a)|b)\1/.match("b").should == nil
  end

  it "ignores backreferences > 1000" do
    /\99999/.match("99999")[0].should == "99999"
  end

  it "0 is not a valid backreference" do
    -> { Regexp.new("\\k<0>") }.should raise_error(RegexpError)
  end

  it "allows numeric conditional backreferences" do
    /(a)(?(1)a|b)/.match("aa").to_a.should == [ "aa", "a" ]
    /(a)(?(<1>)a|b)/.match("aa").to_a.should == [ "aa", "a" ]
    /(a)(?('1')a|b)/.match("aa").to_a.should == [ "aa", "a" ]
  end

  it "allows either <> or '' in named conditional backreferences" do
    -> { Regexp.new("(?<a>a)(?(a)a|b)") }.should raise_error(RegexpError)
    /(?<a>a)(?(<a>)a|b)/.match("aa").to_a.should == [ "aa", "a" ]
    /(?<a>a)(?('a')a|b)/.match("aa").to_a.should == [ "aa", "a" ]
  end

  it "allows negative numeric backreferences" do
    /(a)\k<-1>/.match("aa").to_a.should == [ "aa", "a" ]
    /(a)\g<-1>/.match("aa").to_a.should == [ "aa", "a" ]
    /(a)(?(<-1>)a|b)/.match("aa").to_a.should == [ "aa", "a" ]
    /(a)(?('-1')a|b)/.match("aa").to_a.should == [ "aa", "a" ]
  end

  it "delimited numeric backreferences can start with 0" do
    /(a)\k<01>/.match("aa").to_a.should == [ "aa", "a" ]
    /(a)\g<01>/.match("aa").to_a.should == [ "aa", "a" ]
    /(a)(?(01)a|b)/.match("aa").to_a.should == [ "aa", "a" ]
    /(a)(?(<01>)a|b)/.match("aa").to_a.should == [ "aa", "a" ]
    /(a)(?('01')a|b)/.match("aa").to_a.should == [ "aa", "a" ]
  end

  it "regular numeric backreferences cannot start with 0" do
    /(a)\01/.match("aa").should == nil
    /(a)\01/.match("a\x01").to_a.should == [ "a\x01", "a" ]
  end

  it "named capture groups invalidate numeric backreferences" do
    -> { Regexp.new("(?<a>a)\\1") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a>a)\\k<1>") }.should raise_error(RegexpError)
    -> { Regexp.new("(a)(?<a>a)\\1") }.should raise_error(RegexpError)
    -> { Regexp.new("(a)(?<a>a)\\k<1>") }.should raise_error(RegexpError)
  end

  it "treats + or - as the beginning of a level specifier in \\k<> backreferences and (?(...)...|...) conditional backreferences" do
    -> { Regexp.new("(?<a+>a)\\k<a+>") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a+b>a)\\k<a+b>") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a+1>a)\\k<a+1>") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a->a)\\k<a->") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a-b>a)\\k<a-b>") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a-1>a)\\k<a-1>") }.should raise_error(RegexpError)

    -> { Regexp.new("(?<a+>a)(?(<a+>)a|b)") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a+b>a)(?(<a+b>)a|b)") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a+1>a)(?(<a+1>)a|b)") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a->a)(?(<a->)a|b)") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a-b>a)(?(<a-b>)a|b)") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a-1>a)(?(<a-1>)a|b)") }.should raise_error(RegexpError)

    -> { Regexp.new("(?<a+>a)(?('a+')a|b)") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a+b>a)(?('a+b')a|b)") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a+1>a)(?('a+1')a|b)") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a->a)(?('a-')a|b)") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a-b>a)(?('a-b')a|b)") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<a-1>a)(?('a-1')a|b)") }.should raise_error(RegexpError)
  end
end
