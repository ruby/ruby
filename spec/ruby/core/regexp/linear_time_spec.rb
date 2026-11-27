require_relative '../../spec_helper'

describe "Regexp.linear_time?" do
  it "returns true if matching can be done in linear time" do
    Regexp.linear_time?(/a/).should == true
    Regexp.linear_time?('a').should == true
  end

  it "returns true if matching can be done in linear time for a binary Regexp" do
    Regexp.linear_time?(/[\x80-\xff]/n).should == true
  end

  it "return false if matching can't be done in linear time" do
    Regexp.linear_time?(/(a)\1/).should == false
    Regexp.linear_time?("(a)\\1").should == false
  end

  it "accepts flags for string argument" do
    Regexp.linear_time?('a', Regexp::IGNORECASE).should == true
  end

  it "warns about flags being ignored for regexp arguments" do
    -> {
      Regexp.linear_time?(/a/, Regexp::IGNORECASE)
    }.should complain(/warning: flags ignored/)
  end

  it "returns true for positive lookahead" do
    Regexp.linear_time?(/a*(?:(?=a*)a)*b/).should == true
  end

  it "returns true for positive lookbehind" do
    Regexp.linear_time?(/a*(?:(?<=a)a*)*b/).should == true
  end

  it "returns true for negative lookbehind" do
    Regexp.linear_time?(/a*(?:(?<!a)a*)*b/).should == true
  end

  # There are two known ways to make Regexp linear:
  # * Using a DFA (deterministic finite-state automaton) Regexp engine, which always matches in linear time (e.g. TruffleRuby with TRegex)
  # * Caching position and state to avoid catastrophic backtracking (e.g. CRuby: https://bugs.ruby-lang.org/issues/19104)
  #
  # Both approach should be allowed and given that DFA Regexp engines
  # are much faster there should be no specs preventing using them.
  uses_regexp_caching = RUBY_ENGINE == 'ruby'
  uses_dfa_regexp_engine = !uses_regexp_caching

  # The following specs should not be relied upon,
  # they are here only to illustrate differences between Regexp engines.
  guard -> { uses_regexp_caching } do
    it "returns true for negative lookahead" do
      Regexp.linear_time?(/a*(?:(?!a*)a*)*b/).should == true
    end

    it "returns true for atomic groups" do
      Regexp.linear_time?(/a*(?:(?>a)a*)*b/).should == true
    end

    it "returns true for possessive quantifiers" do
      Regexp.linear_time?(/a*(?:(?:a)?+a*)*b/).should == true
    end

    it "returns true for positive lookbehind with capture group" do
      Regexp.linear_time?(/.(?<=(a))/).should == true
    end
  end

  # The following specs should not be relied upon,
  # they are here only to illustrate differences between Regexp engines.
  guard -> { uses_dfa_regexp_engine } do
    it "returns true for non-recursive subexpression call" do
      Regexp.linear_time?(/(?<a>a){0}\g<a>/).should == true
    end

    it "returns true for positive lookahead with capture group" do
      Regexp.linear_time?(/x+(?=(a))/).should == true
    end
  end
end
