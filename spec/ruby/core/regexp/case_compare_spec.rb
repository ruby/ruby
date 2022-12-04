require_relative '../../spec_helper'

describe "Regexp#===" do
  it "is true if there is a match" do
    (/abc/ === "aabcc").should be_true
  end

  it "is false if there is no match" do
    (/abc/ === "xyz").should be_false
  end

  it "returns true if it matches a Symbol" do
    (/a/ === :a).should be_true
  end

  it "returns false if it does not match a Symbol" do
    (/a/ === :b).should be_false
  end

  # mirroring https://github.com/ruby/ruby/blob/master/test/ruby/test_regexp.rb
  it "returns false if the other value cannot be coerced to a string" do
    (/abc/ === nil).should be_false
    (/abc/ === /abc/).should be_false
  end

  it "uses #to_str on string-like objects" do
    stringlike = Class.new do
      def to_str
        "abc"
      end
    end.new

    (/abc/ === stringlike).should be_true
  end
end
