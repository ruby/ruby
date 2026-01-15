require_relative '../../spec_helper'
require_relative '../fixtures/classes'

describe "empty checks in Regexps" do

  it "allow extra empty iterations" do
    /()?/.match("").to_a.should == ["", ""]
    /(a*)?/.match("").to_a.should == ["", ""]
    /(a*)*/.match("").to_a.should == ["", ""]
    # The bounds are high to avoid DFA-based matchers in implementations
    # and to check backtracking behavior.
    /(?:a|()){500,1000}/.match("a" * 500).to_a.should == ["a" * 500, ""]

    # Variations with non-greedy loops.
    /()??/.match("").to_a.should == ["", nil]
    /(a*?)?/.match("").to_a.should == ["", ""]
    /(a*)??/.match("").to_a.should == ["", nil]
    /(a*?)??/.match("").to_a.should == ["", nil]
    /(a*?)*/.match("").to_a.should == ["", ""]
    /(a*)*?/.match("").to_a.should == ["", nil]
    /(a*?)*?/.match("").to_a.should == ["", nil]
  end

  it "allow empty iterations in the middle of a loop" do
    # One empty iteration between a's and b's.
    /(a|\2b|())*/.match("aaabbb").to_a.should == ["aaabbb", "", ""]
    /(a|\2b|()){2,4}/.match("aaabbb").to_a.should == ["aaa", "", ""]

    # Two empty iterations between a's and b's.
    /(a|\2b|\3()|())*/.match("aaabbb").to_a.should == ["aaabbb", "", "", ""]
    /(a|\2b|\3()|()){2,4}/.match("aaabbb").to_a.should == ["aaa", "", nil, ""]

    # Check that the empty iteration correctly updates the loop counter.
    /(a|\2b|()){20,24}/.match("a" * 20 + "b" * 5).to_a.should == ["a" * 20 + "b" * 3, "b", ""]

    # Variations with non-greedy loops.
    /(a|\2b|())*?/.match("aaabbb").to_a.should == ["", nil, nil]
    /(a|\2b|()){2,4}/.match("aaabbb").to_a.should == ["aaa", "", ""]
    /(a|\2b|\3()|())*?/.match("aaabbb").to_a.should == ["", nil, nil, nil]
    /(a|\2b|\3()|()){2,4}/.match("aaabbb").to_a.should == ["aaa", "", nil, ""]
    /(a|\2b|()){20,24}/.match("a" * 20 + "b" * 5).to_a.should == ["a" * 20 + "b" * 3, "b", ""]
  end

  it "make the Regexp proceed past the quantified expression on failure" do
    # If the contents of the ()* quantified group are empty (i.e., they fail
    # the empty check), the loop will abort. It will not try to backtrack
    # and try other alternatives (e.g. matching the "a") like in other Regexp
    # dialects such as ECMAScript.
    /(?:|a)*/.match("aaa").to_a.should == [""]
    /(?:()|a)*/.match("aaa").to_a.should == ["", ""]
    /(|a)*/.match("aaa").to_a.should == ["", ""]
    /(()|a)*/.match("aaa").to_a.should == ["", "", ""]

    # Same expressions, but with backreferences, to force the use of non-DFA-based
    # engines.
    /()\1(?:|a)*/.match("aaa").to_a.should == ["", ""]
    /()\1(?:()|a)*/.match("aaa").to_a.should == ["", "", ""]
    /()\1(|a)*/.match("aaa").to_a.should == ["", "", ""]
    /()\1(()|a)*/.match("aaa").to_a.should == ["", "", "", ""]

    # Variations with other zero-width contents of the quantified
    # group: backreferences, capture groups, lookarounds
    /()(?:\1|a)*/.match("aaa").to_a.should == ["", ""]
    /()(?:()\1|a)*/.match("aaa").to_a.should == ["", "", ""]
    /()(?:(\1)|a)*/.match("aaa").to_a.should == ["", "", ""]
    /()(?:\1()|a)*/.match("aaa").to_a.should == ["", "", ""]
    /()(\1|a)*/.match("aaa").to_a.should == ["", "", ""]
    /()(()\1|a)*/.match("aaa").to_a.should == ["", "", "", ""]
    /()((\1)|a)*/.match("aaa").to_a.should == ["", "", "", ""]
    /()(\1()|a)*/.match("aaa").to_a.should == ["", "", "", ""]

    /(?:(?=a)|a)*/.match("aaa").to_a.should == [""]
    /(?:(?=a)()|a)*/.match("aaa").to_a.should == ["", ""]
    /(?:()(?=a)|a)*/.match("aaa").to_a.should == ["", ""]
    /(?:((?=a))|a)*/.match("aaa").to_a.should == ["", ""]
    /()\1(?:(?=a)|a)*/.match("aaa").to_a.should == ["", ""]
    /()\1(?:(?=a)()|a)*/.match("aaa").to_a.should == ["", "", ""]
    /()\1(?:()(?=a)|a)*/.match("aaa").to_a.should == ["", "", ""]
    /()\1(?:((?=a))|a)*/.match("aaa").to_a.should == ["", "", ""]

    # Variations with non-greedy loops.
    /(?:|a)*?/.match("aaa").to_a.should == [""]
    /(?:()|a)*?/.match("aaa").to_a.should == ["", nil]
    /(|a)*?/.match("aaa").to_a.should == ["", nil]
    /(()|a)*?/.match("aaa").to_a.should == ["", nil, nil]

    /()\1(?:|a)*?/.match("aaa").to_a.should == ["", ""]
    /()\1(?:()|a)*?/.match("aaa").to_a.should == ["", "", nil]
    /()\1(|a)*?/.match("aaa").to_a.should == ["", "", nil]
    /()\1(()|a)*?/.match("aaa").to_a.should == ["", "", nil, nil]

    /()(?:\1|a)*?/.match("aaa").to_a.should == ["", ""]
    /()(?:()\1|a)*?/.match("aaa").to_a.should == ["", "", nil]
    /()(?:(\1)|a)*?/.match("aaa").to_a.should == ["", "", nil]
    /()(?:\1()|a)*?/.match("aaa").to_a.should == ["", "", nil]
    /()(\1|a)*?/.match("aaa").to_a.should == ["", "", nil]
    /()(()\1|a)*?/.match("aaa").to_a.should == ["", "", nil, nil]
    /()((\1)|a)*?/.match("aaa").to_a.should == ["", "", nil, nil]
    /()(\1()|a)*?/.match("aaa").to_a.should == ["", "", nil, nil]

    /(?:(?=a)|a)*?/.match("aaa").to_a.should == [""]
    /(?:(?=a)()|a)*?/.match("aaa").to_a.should == ["", nil]
    /(?:()(?=a)|a)*?/.match("aaa").to_a.should == ["", nil]
    /(?:((?=a))|a)*?/.match("aaa").to_a.should == ["", nil]
    /()\1(?:(?=a)|a)*?/.match("aaa").to_a.should == ["", ""]
    /()\1(?:(?=a)()|a)*?/.match("aaa").to_a.should == ["", "", nil]
    /()\1(?:()(?=a)|a)*?/.match("aaa").to_a.should == ["", "", nil]
    /()\1(?:((?=a))|a)*?/.match("aaa").to_a.should == ["", "", nil]
  end

  it "shouldn't cause the Regexp parser to get stuck in a loop" do
    /(|a|\2b|())*/.match("aaabbb").to_a.should == ["", "", nil]
    /(a||\2b|())*/.match("aaabbb").to_a.should == ["aaa", "", nil]
    /(a|\2b||())*/.match("aaabbb").to_a.should == ["aaa", "", nil]
    /(a|\2b|()|)*/.match("aaabbb").to_a.should == ["aaabbb", "", ""]
    /(()|a|\3b|())*/.match("aaabbb").to_a.should == ["", "", "", nil]
    /(a|()|\3b|())*/.match("aaabbb").to_a.should == ["aaa", "", "", nil]
    /(a|\2b|()|())*/.match("aaabbb").to_a.should == ["aaabbb", "", "", nil]
    /(a|\3b|()|())*/.match("aaabbb").to_a.should == ["aaa", "", "", nil]
    /(a|()|())*/.match("aaa").to_a.should == ["aaa", "", "", nil]
    /^(()|a|())*$/.match("aaa").to_a.should == ["aaa", "", "", nil]

    # Variations with non-greedy loops.
    /(|a|\2b|())*?/.match("aaabbb").to_a.should == ["", nil, nil]
    /(a||\2b|())*?/.match("aaabbb").to_a.should == ["", nil, nil]
    /(a|\2b||())*?/.match("aaabbb").to_a.should == ["", nil, nil]
    /(a|\2b|()|)*?/.match("aaabbb").to_a.should == ["", nil, nil]
    /(()|a|\3b|())*?/.match("aaabbb").to_a.should == ["", nil, nil, nil]
    /(a|()|\3b|())*?/.match("aaabbb").to_a.should == ["", nil, nil, nil]
    /(a|\2b|()|())*?/.match("aaabbb").to_a.should == ["", nil, nil, nil]
    /(a|\3b|()|())*?/.match("aaabbb").to_a.should == ["", nil, nil, nil]
    /(a|()|())*?/.match("aaa").to_a.should == ["", nil, nil, nil]
    /^(()|a|())*?$/.match("aaa").to_a.should == ["aaa", "a", "", nil]
  end
end
