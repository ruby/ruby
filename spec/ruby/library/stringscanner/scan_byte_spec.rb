require_relative '../../spec_helper'
require 'strscan'

version_is StringScanner::Version, "3.1.1" do # ruby_version_is "3.4"
  describe "StringScanner#scan_byte" do
    it "scans one byte and returns it as on Integer" do
      s = StringScanner.new('abc') # "abc".bytes => [97, 98, 99]
      s.scan_byte.should == 97
      s.scan_byte.should == 98
      s.scan_byte.should == 99
    end

    it "is not multi-byte character sensitive" do
      s = StringScanner.new("あ") # "あ".bytes => [227, 129, 130]
      s.scan_byte.should == 227
      s.scan_byte.should == 129
      s.scan_byte.should == 130
    end

    it "returns nil at the end of the string" do
      s = StringScanner.new('a')
      s.scan_byte # skip one
      s.scan_byte.should == nil
      s.pos.should == 1
    end

    it "changes current position" do
      s = StringScanner.new('abc')
      s.pos.should == 0
      s.scan_byte
      s.pos.should == 1
    end

    it "sets the last match result" do
      s = StringScanner.new('abc')
      s.pos = 1
      s.scan_byte

      s.pre_match.should == "a"
      s.matched.should == "b"
      s.post_match.should == "c"
    end

    describe "#[] successive call with a capture group name" do
      # https://github.com/ruby/strscan/issues/139
      version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
        it "returns nil" do
          s = StringScanner.new("abc")
          s.scan_byte
          s.should.matched?
          s[:a].should be_nil
        end
      end
      version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.3"
        it "raises IndexError" do
          s = StringScanner.new("abc")
          s.scan_byte
          s.should.matched?
          -> { s[:a] }.should raise_error(IndexError)
        end
      end

      it "returns a matching character when given Integer index" do
        s = StringScanner.new("This is a test")
        s.scan_byte
        s[0].should == "T"
      end

      # https://github.com/ruby/strscan/issues/135
      version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
        it "ignores the previous matching with Regexp" do
          s = StringScanner.new("abc")

          s.exist?(/(?<a>a)/)
          s.should.matched?
          s[:a].should == "a"

          s.scan_byte
          s.should.matched?
          s[:a].should == nil
        end
      end
      version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
        it "ignores the previous matching with Regexp" do
          s = StringScanner.new("abc")

          s.exist?(/(?<a>a)/)
          s.should.matched?
          s[:a].should == "a"

          s.scan_byte
          s.should.matched?
          -> { s[:a] }.should raise_error(IndexError)
        end
      end
    end
  end
end
