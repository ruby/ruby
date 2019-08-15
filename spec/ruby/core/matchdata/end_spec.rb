# -*- encoding: utf-8 -*-

require_relative '../../spec_helper'

describe "MatchData#end" do
  context "when passed an integer argument" do
    it "returns the character offset of the end of the nth element" do
      match_data = /(.)(.)(\d+)(\d)/.match("THX1138.")
      match_data.end(0).should == 7
      match_data.end(2).should == 3
    end

    it "returns nil when the nth match isn't found" do
      match_data = /something is( not)? (right)/.match("something is right")
      match_data.end(1).should be_nil
    end

    it "returns the character offset for multi-byte strings" do
      match_data = /(.)(.)(\d+)(\d)/.match("TñX1138.")
      match_data.end(0).should == 7
      match_data.end(2).should == 3
    end

    not_supported_on :opal do
      it "returns the character offset for multi-byte strings with unicode regexp" do
        match_data = /(.)(.)(\d+)(\d)/u.match("TñX1138.")
        match_data.end(0).should == 7
        match_data.end(2).should == 3
      end
    end

    it "tries to convert the passed argument to an Integer using #to_int" do
      obj = mock('to_int')
      obj.should_receive(:to_int).and_return(2)

      match_data = /(.)(.)(\d+)(\d)/.match("THX1138.")
      match_data.end(obj).should == 3
    end
  end

  context "when passed a String argument" do
    it "return the character offset of the start of the named capture" do
      match_data = /(?<a>.)(.)(?<b>\d+)(\d)/.match("THX1138.")
      match_data.end("a").should == 2
      match_data.end("b").should == 6
    end

    it "returns the character offset for multi byte strings" do
      match_data = /(?<a>.)(.)(?<b>\d+)(\d)/.match("TñX1138.")
      match_data.end("a").should == 2
      match_data.end("b").should == 6
    end

    not_supported_on :opal do
      it "returns the character offset for multi byte strings with unicode regexp" do
        match_data = /(?<a>.)(.)(?<b>\d+)(\d)/u.match("TñX1138.")
        match_data.end("a").should == 2
        match_data.end("b").should == 6
      end
    end

    it "returns the character offset for the farthest match when multiple named captures use the same name" do
      match_data = /(?<a>.)(.)(?<a>\d+)(\d)/.match("THX1138.")
      match_data.end("a").should == 6
    end

    it "returns the character offset for multi-byte names" do
      match_data = /(?<æ>.)(.)(?<b>\d+)(\d)/.match("THX1138.")
      match_data.end("æ").should == 2
    end
  end

  context "when passed a Symbol argument" do
    it "return the character offset of the start of the named capture" do
      match_data = /(?<a>.)(.)(?<b>\d+)(\d)/.match("THX1138.")
      match_data.end(:a).should == 2
      match_data.end(:b).should == 6
    end

    it "returns the character offset for multi byte strings" do
      match_data = /(?<a>.)(.)(?<b>\d+)(\d)/.match("TñX1138.")
      match_data.end(:a).should == 2
      match_data.end(:b).should == 6
    end

    not_supported_on :opal do
      it "returns the character offset for multi byte strings with unicode regexp" do
        match_data = /(?<a>.)(.)(?<b>\d+)(\d)/u.match("TñX1138.")
        match_data.end(:a).should == 2
        match_data.end(:b).should == 6
      end
    end

    it "returns the character offset for the farthest match when multiple named captures use the same name" do
      match_data = /(?<a>.)(.)(?<a>\d+)(\d)/.match("THX1138.")
      match_data.end(:a).should == 6
    end

    it "returns the character offset for multi-byte names" do
      match_data = /(?<æ>.)(.)(?<b>\d+)(\d)/.match("THX1138.")
      match_data.end(:æ).should == 2
    end
  end
end
