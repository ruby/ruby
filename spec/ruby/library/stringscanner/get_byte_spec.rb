# encoding: binary
require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#get_byte" do
  it "scans one byte and returns it" do
    s = StringScanner.new('abc5.')
    s.get_byte.should == 'a'
    s.get_byte.should == 'b'
    s.get_byte.should == 'c'
    s.get_byte.should == '5'
    s.get_byte.should == '.'
  end

  it "is not multi-byte character sensitive" do
    s = StringScanner.new("\244\242")
    s.get_byte.should == "\244"
    s.get_byte.should == "\242"
  end

  it "returns nil at the end of the string" do
    # empty string case
    s = StringScanner.new('')
    s.get_byte.should == nil
    s.get_byte.should == nil

    # non-empty string case
    s = StringScanner.new('a')
    s.get_byte # skip one
    s.get_byte.should == nil
  end

  describe "#[] successive call with a capture group name" do
    # https://github.com/ruby/strscan/issues/139
    version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
      it "returns nil" do
        s = StringScanner.new("This is a test")
        s.get_byte
        s.should.matched?
        s[:a].should be_nil
      end
    end
    version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.3"
      it "raises IndexError" do
        s = StringScanner.new("This is a test")
        s.get_byte
        s.should.matched?
        -> { s[:a] }.should raise_error(IndexError)
      end
    end

    it "returns a matching character when given Integer index" do
      s = StringScanner.new("This is a test")
      s.get_byte
      s[0].should == "T"
    end

    # https://github.com/ruby/strscan/issues/135
    version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
      it "ignores the previous matching with Regexp" do
        s = StringScanner.new("This is a test")
        s.exist?(/(?<a>This)/)
        s.should.matched?
        s[:a].should == "This"

        s.get_byte
        s.should.matched?
        s[:a].should be_nil
      end
    end
    version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.3"
      it "ignores the previous matching with Regexp" do
        s = StringScanner.new("This is a test")
        s.exist?(/(?<a>This)/)
        s.should.matched?
        s[:a].should == "This"

        s.get_byte
        s.should.matched?
        -> { s[:a] }.should raise_error(IndexError)
      end
    end
  end
end
