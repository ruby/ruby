require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "MatchData#pre_match" do
  it "returns the string before the match, equiv. special var $`" do
    /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").pre_match.should == 'T'
    $`.should == 'T'
  end

  it "sets the encoding to the encoding of the source String" do
    str = "abc".force_encoding Encoding::EUC_JP
    str.match(/b/).pre_match.encoding.should equal(Encoding::EUC_JP)
  end

  it "sets an empty result to the encoding of the source String" do
    str = "abc".force_encoding Encoding::ISO_8859_1
    str.match(/a/).pre_match.encoding.should equal(Encoding::ISO_8859_1)
  end

  it "returns an instance of String when given a String subclass" do
    str = MatchDataSpecs::MyString.new("THX1138: The Movie")
    /(.)(.)(\d+)(\d)/.match(str).pre_match.should be_an_instance_of(String)
  end
end
