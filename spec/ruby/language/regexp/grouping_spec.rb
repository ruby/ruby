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
   -> { eval "/(hay(st)ack/" }.should raise_error(SyntaxError)
  end

  it "supports (?: ) (non-capturing group)" do
    /(?:foo)(bar)/.match("foobar").to_a.should == ["foobar", "bar"]
    # Parsing precedence
    /(?:xdigit:)/.match("xdigit:").to_a.should == ["xdigit:"]
  end

  it "group names cannot start with digits or minus" do
    -> { Regexp.new("(?<1a>a)") }.should raise_error(RegexpError)
    -> { Regexp.new("(?<-a>a)") }.should raise_error(RegexpError)
  end

  it "ignore capture groups in line comments" do
    /^
     (a) # there is a capture group on this line
     b   # there is no capture group on this line (not even here)
     $/x.match("ab").to_a.should == [ "ab", "a" ]
  end

  it "does not consider # inside a character class as a comment" do
    # From https://github.com/rubocop/rubocop/blob/39fcf1c568/lib/rubocop/cop/utils/format_string.rb#L18
    regexp = /
        % (?<type>%) # line comment
      | % (?<flags>(?-mix:[ #0+-]|(?-mix:(\d+)\$))*) (?#group comment)
        (?:
          (?: (?-mix:(?<width>(?-mix:\d+|(?-mix:\*(?-mix:(\d+)\$)?))))? (?-mix:\.(?<precision>(?-mix:\d+|(?-mix:\*(?-mix:(\d+)\$)?))))? (?-mix:<(?<name>\w+)>)?
            | (?-mix:(?<width>(?-mix:\d+|(?-mix:\*(?-mix:(\d+)\$)?))))? (?-mix:<(?<name>\w+)>) (?-mix:\.(?<precision>(?-mix:\d+|(?-mix:\*(?-mix:(\d+)\$)?))))?
            | (?-mix:<(?<name>\w+)>) (?<more_flags>(?-mix:[ #0+-]|(?-mix:(\d+)\$))*) (?-mix:(?<width>(?-mix:\d+|(?-mix:\*(?-mix:(\d+)\$)?))))? (?-mix:\.(?<precision>(?-mix:\d+|(?-mix:\*(?-mix:(\d+)\$)?))))?
          ) (?-mix:(?<type>[bBdiouxXeEfgGaAcps]))
          | (?-mix:(?<width>(?-mix:\d+|(?-mix:\*(?-mix:(\d+)\$)?))))? (?-mix:\.(?<precision>(?-mix:\d+|(?-mix:\*(?-mix:(\d+)\$)?))))? (?-mix:\{(?<name>\w+)\})
        )
    /x
    regexp.named_captures.should == {
      "type" => [1, 13],
      "flags" => [2],
      "width" => [3, 6, 11, 14],
      "precision" => [4, 8, 12, 15],
      "name" => [5, 7, 9, 16],
      "more_flags" => [10]
    }
    match = regexp.match("%6.3f")
    match[:width].should == '6'
    match[:precision].should == '3'
    match[:type].should == 'f'
    match.to_a.should == [ "%6.3f", nil, "", "6", "3"] + [nil] * 8 + ["f"] + [nil] * 3
  end
end
