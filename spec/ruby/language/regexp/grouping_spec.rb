require_relative '../../spec_helper'
require_relative '../fixtures/classes'

describe "Regexps with grouping" do
  it "support ()" do
    /(a)/.match("a").to_a.should == ["a", "a"]
  end

  it "allows groups to be nested" do
    md = /(hay(st)a)ck/.match('haystack')
    md.to_a.should == ['haystack','haysta', 'st']
  end

  it "raises a SyntaxError when parentheses aren't balanced" do
   lambda { eval "/(hay(st)ack/" }.should raise_error(SyntaxError)
  end

  it "supports (?: ) (non-capturing group)" do
    /(?:foo)(bar)/.match("foobar").to_a.should == ["foobar", "bar"]
    # Parsing precedence
    /(?:xdigit:)/.match("xdigit:").to_a.should == ["xdigit:"]
  end
end
