require_relative '../../spec_helper'

describe "MatchData#dup" do
  it "duplicates the match data" do
    original = /ll/.match("hello")
    original.instance_variable_set(:@custom_ivar, 42)
    duplicate = original.dup

    duplicate.instance_variable_get(:@custom_ivar).should == 42
    original.regexp.should == duplicate.regexp
    original.string.should == duplicate.string
    original.offset(0).should == duplicate.offset(0)
  end
end
