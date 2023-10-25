# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'

describe "Regexp#source" do
  it "returns the original string of the pattern" do
    not_supported_on :opal do
      /ab+c/ix.source.should == "ab+c"
    end
    /x(.)xz/.source.should == "x(.)xz"
  end

  it "keeps escape sequences as is" do
    /\x20\+/.source.should == '\x20\+'
  end

  describe "escaping" do
    it "keeps escaping of metacharacter" do
      /\$/.source.should == "\\$"
    end

    it "keeps escaping of metacharacter used as a terminator" do
      %r+\++.source.should == "\\+"
    end

    it "removes escaping of non-metacharacter used as a terminator" do
      %r@\@@.source.should == "@"
    end

    it "keeps escaping of non-metacharacter not used as a terminator" do
      /\@/.source.should == "\\@"
    end
  end

  not_supported_on :opal do
    it "has US-ASCII encoding when created from an ASCII-only \\u{} literal" do
      re = /[\u{20}-\u{7E}]/
      re.source.encoding.should equal(Encoding::US_ASCII)
    end
  end

  not_supported_on :opal do
    it "has UTF-8 encoding when created from a non-ASCII-only \\u{} literal" do
      re = /[\u{20}-\u{7EE}]/
      re.source.encoding.should equal(Encoding::UTF_8)
    end
  end
end
