# -*- encoding: utf-8 -*-

require_relative '../../spec_helper'

ruby_version_is "3.1" do
  describe "MatchData#match" do
    it "returns the corresponding match when given an Integer" do
      md = /(.)(.)(\d+)(\d)/.match("THX1138.")

      md.match(0).should == 'HX1138'
      md.match(1).should == 'H'
      md.match(2).should == 'X'
      md.match(3).should == '113'
      md.match(4).should == '8'
    end

    it "returns nil on non-matching index matches" do
      md = /\d+(\w)?/.match("THX1138.")
      md.match(1).should == nil
    end

    it "returns the corresponding named match when given a Symbol" do
      md = 'haystack'.match(/(?<t>t(?<a>ack))/)
      md.match(:a).should == 'ack'
      md.match(:t).should == 'tack'
    end

    it "returns nil on non-matching index matches" do
      md = 'haystack'.match(/(?<t>t)(?<a>all)?/)
      md.match(:t).should == 't'
      md.match(:a).should == nil
    end
  end
end
