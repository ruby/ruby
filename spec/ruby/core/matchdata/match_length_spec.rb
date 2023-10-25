# -*- encoding: utf-8 -*-

require_relative '../../spec_helper'

ruby_version_is "3.1" do
  describe "MatchData#match_length" do
    it "returns the length of the corresponding match when given an Integer" do
      md = /(.)(.)(\d+)(\d)/.match("THX1138.")

      md.match_length(0).should == 6
      md.match_length(1).should == 1
      md.match_length(2).should == 1
      md.match_length(3).should == 3
      md.match_length(4).should == 1
    end

    it "returns nil on non-matching index matches" do
      md = /\d+(\w)?/.match("THX1138.")
      md.match_length(1).should == nil
    end

    it "returns the length of the corresponding named match when given a Symbol" do
      md = 'haystack'.match(/(?<t>t(?<a>ack))/)
      md.match_length(:a).should == 3
      md.match_length(:t).should == 4
    end

    it "returns nil on non-matching index matches" do
      md = 'haystack'.match(/(?<t>t)(?<a>all)?/)
      md.match_length(:t).should == 1
      md.match_length(:a).should == nil
    end
  end
end
