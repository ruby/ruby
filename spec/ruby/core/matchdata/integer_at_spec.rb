# -*- encoding: utf-8 -*-

require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "MatchData#integer_at" do
    it "converts the corresponding match to an Integer and returns it when given an Integer" do
      md = /(\d{4})(\d{2})(\d{2})/.match("20260308")
      md.integer_at(0).should == 20260308
      md.integer_at(1).should == 2026
      md.integer_at(2).should == 3
    end

    it "returns nil on non-matching index matches" do
      md = /\b(\d)?\b/.match("THX1138.")
      md.integer_at(1).should == nil
    end

    it "returns nil on non-integer matches" do
      md = /(\w)?/.match("THX1138.")
      md.integer_at(1).should == nil
    end

    it "converts the match to an Integer in the given base" do
      md = /\w+/.match("0c")
      md.integer_at(0).should == 0
      md.integer_at(0, 16).should == 12
    end

    it "converts the match to an Integer in the prefix when given base is zero" do
      /\w+/.match("010").integer_at(0, 0).should == 010
      /\w+/.match("0x10").integer_at(0, 0).should == 0x10
      /\w+/.match("0d10").integer_at(0, 0).should == 0d10
      /\w+/.match("0o10").integer_at(0, 0).should == 0o10
      /\w+/.match("0b10").integer_at(0, 0).should == 0b10
    end
  end
end
