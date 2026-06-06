require_relative '../../spec_helper'

describe "Symbol#to_s" do
  it "returns the string corresponding to self" do
    :rubinius.to_s.should == "rubinius"
    :squash.to_s.should == "squash"
    :[].to_s.should == "[]"
    :@ruby.to_s.should == "@ruby"
    :@@ruby.to_s.should == "@@ruby"
  end

  it "returns a String in the same encoding as self" do
    string = "ruby".encode("US-ASCII")
    symbol = string.to_sym

    symbol.to_s.encoding.should == Encoding::US_ASCII
  end

  ruby_version_is "3.4" do
    it "warns about mutating returned string" do
      -> { :bad!.to_s.upcase! }.should complain(/warning: string returned by :bad!.to_s will be frozen in the future/)
    end

    it "does not warn about mutation when Warning[:deprecated] is false" do
      deprecated = Warning[:deprecated]
      Warning[:deprecated] = false
      -> { :bad!.to_s.upcase! }.should_not complain
    ensure
      Warning[:deprecated] = deprecated
    end
  end
end
