require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#scan_until" do
  before do
    @s = StringScanner.new("This is a test")
  end

  it "returns the substring up to and including the end of the match" do
    @s.scan_until(/a/).should == "This is a"
  end

  it "sets the last match result" do
    @s.scan_until(/a/)

    @s.pre_match.should == "This is "
    @s.matched.should == "a"
    @s.post_match.should == " test"
  end

  it "returns nil if there's no match" do
    @s.scan_until(/\d/).should == nil
  end

  it "can match anchors properly" do
    @s.scan(/T/)
    @s.scan_until(/^h/).should == "h"
  end

  version_is StringScanner::Version, ""..."3.1.1" do # ruby_version_is ""..."3.4"
    it "raises TypeError if given a String" do
      -> {
        @s.scan_until('T')
      }.should raise_error(TypeError, 'wrong argument type String (expected Regexp)')
    end
  end

  version_is StringScanner::Version, "3.1.1" do # ruby_version_is "3.4"
    it "searches a substring in the rest part of a string if given a String" do
      @s.scan_until("a").should == "This is a"
    end

    # https://github.com/ruby/strscan/issues/131
    version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.1"
      it "sets the last match result if given a String" do
        @s.scan_until("a")

        @s.pre_match.should == ""
        @s.matched.should == "This is a"
        @s.post_match.should == " test"
      end
    end

    version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4"
      it "sets the last match result if given a String" do
        @s.scan_until("a")

        @s.pre_match.should == "This is "
        @s.matched.should == "a"
        @s.post_match.should == " test"
      end
    end
  end

  describe "#[] successive call with a capture group name" do
    context "when #scan_until was called with a Regexp pattern" do
      it "returns matched substring when matching succeeded" do
        @s.scan_until(/(?<a>This)/)
        @s.should.matched?
        @s[:a].should == "This"
      end

      it "returns nil when matching failed" do
        @s.scan_until(/(?<a>2008)/)
        @s.should_not.matched?
        @s[:a].should be_nil
      end
    end

    version_is StringScanner::Version, "3.1.1" do # ruby_version_is "3.4"
      context "when #scan_until was called with a String pattern" do
        # https://github.com/ruby/strscan/issues/139
        version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
          it "returns nil when matching succeeded" do
            @s.scan_until("This")
            @s.should.matched?
            @s[:a].should be_nil
          end
        end
        version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.3"
          it "raises IndexError when matching succeeded" do
            @s.scan_until("This")
            @s.should.matched?
            -> { @s[:a] }.should raise_error(IndexError)
          end
        end

        it "returns nil when matching failed" do
          @s.scan_until("2008")
          @s.should_not.matched?
          @s[:a].should be_nil
        end

        it "returns a matching substring when given Integer index" do
          @s.scan_until("This")
          @s[0].should == "This"
        end

        # https://github.com/ruby/strscan/issues/135
        version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
          it "ignores the previous matching with Regexp" do
            @s.exist?(/(?<a>This)/)
            @s.should.matched?
            @s[:a].should == "This"

            @s.scan_until("This")
            @s.should.matched?
            @s[:a].should be_nil
          end
        end
        version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4"
          it "ignores the previous matching with Regexp" do
            @s.exist?(/(?<a>This)/)
            @s.should.matched?
            @s[:a].should == "This"

            @s.scan_until("This")
            @s.should.matched?
            -> { @s[:a] }.should raise_error(IndexError)
          end
        end
      end
    end
  end
end
