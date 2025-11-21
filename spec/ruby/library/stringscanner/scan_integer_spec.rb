require_relative '../../spec_helper'
require 'strscan'

version_is StringScanner::Version, "3.1.1" do # ruby_version_is "3.4"
  describe "StringScanner#scan_integer" do
    it "returns the matched Integer literal starting from the current position" do
      s = StringScanner.new("42")
      s.scan_integer.should == 42
    end

    it "returns nil when no Integer literal matched starting from the current position" do
      s = StringScanner.new("a42")
      s.scan_integer.should == nil
    end

    it "supports a sign +/-" do
      StringScanner.new("+42").scan_integer.should == 42
      StringScanner.new("-42").scan_integer.should == -42
    end

    it "changes the current position" do
      s = StringScanner.new("42abc")
      s.scan_integer
      s.pos.should == 2
    end

    # https://github.com/ruby/strscan/issues/130
    ruby_bug "", "3.4"..."4.0" do # introduced in strscan v3.1.1
      it "sets the last match result" do
        s = StringScanner.new("42abc")
        s.scan_integer

        s.should.matched?
        s.matched.should == "42"
        s.pre_match.should == ""
        s.post_match.should == "abc"
        s.matched_size.should == 2
      end
    end

    it "raises Encoding::CompatibilityError when a scanned string not is ASCII-compatible encoding" do
      string = "42".encode(Encoding::UTF_16BE)
      s = StringScanner.new(string)

      -> {
        s.scan_integer
      }.should raise_error(Encoding::CompatibilityError, 'ASCII incompatible encoding: UTF-16BE')
    end

    context "given base" do
      it "supports base: 10" do
        s = StringScanner.new("42")
        s.scan_integer(base: 10).should == 42
      end

      it "supports base: 16" do
        StringScanner.new("0xff").scan_integer(base: 16).should == 0xff
        StringScanner.new("-0xff").scan_integer(base: 16).should == -0xff
        StringScanner.new("0xFF").scan_integer(base: 16).should == 0xff
        StringScanner.new("-0xFF").scan_integer(base: 16).should == -0xff
        StringScanner.new("ff").scan_integer(base: 16).should == 0xff
        StringScanner.new("-ff").scan_integer(base: 16).should == -0xff
      end

      it "raises ArgumentError when passed not supported base" do
        -> {
          StringScanner.new("42").scan_integer(base: 5)
        }.should raise_error(ArgumentError, "Unsupported integer base: 5, expected 10 or 16")
      end

      version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
        it "does not match '0x' prefix on its own" do
          StringScanner.new("0x").scan_integer(base: 16).should == nil
          StringScanner.new("-0x").scan_integer(base: 16).should == nil
          StringScanner.new("+0x").scan_integer(base: 16).should == nil
        end
      end

      version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.3"
        it "matches '0' in a '0x' that is followed by non-hex characters" do
          StringScanner.new("0x!@#").scan_integer(base: 16).should == 0
          StringScanner.new("-0x!@#").scan_integer(base: 16).should == 0
          StringScanner.new("+0x!@#").scan_integer(base: 16).should == 0
        end

        it "matches '0' in a '0x' located in the end of a string" do
          StringScanner.new("0x").scan_integer(base: 16).should == 0
          StringScanner.new("-0x").scan_integer(base: 16).should == 0
          StringScanner.new("+0x").scan_integer(base: 16).should == 0
        end
      end
    end
  end

  describe "#[] successive call with a capture group name" do
    # https://github.com/ruby/strscan/issues/139
    version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
      it "returns nil substring when matching succeeded" do
        s = StringScanner.new("42")
        s.scan_integer
        s.should.matched?
        s[:a].should == nil
      end
    end
    version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.3"
      it "raises IndexError when matching succeeded" do
        s = StringScanner.new("42")
        s.scan_integer
        s.should.matched?
        -> { s[:a] }.should raise_error(IndexError)
      end
    end

    it "returns nil when matching failed" do
      s = StringScanner.new("a42")
      s.scan_integer
      s.should_not.matched?
      s[:a].should be_nil
    end

    version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4"
      it "returns a matching substring when given Integer index" do
        s = StringScanner.new("42")
        s.scan_integer
        s[0].should == "42"
      end
    end

    # https://github.com/ruby/strscan/issues/135
    version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
      it "does not ignore the previous matching with Regexp" do
        s = StringScanner.new("42")

        s.exist?(/(?<a>42)/)
        s.should.matched?
        s[:a].should == "42"

        s.scan_integer
        s.should.matched?
        s[:a].should == "42"
      end
    end
    version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4"
      it "ignores the previous matching with Regexp" do
        s = StringScanner.new("42")

        s.exist?(/(?<a>42)/)
        s.should.matched?
        s[:a].should == "42"

        s.scan_integer
        s.should.matched?
        -> { s[:a] }.should raise_error(IndexError)
      end
    end
  end
end
