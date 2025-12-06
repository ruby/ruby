require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#check" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "returns the value that scan would return, without advancing the scan pointer" do
    @s.check(/This/).should == "This"
    @s.matched.should == "This"
    @s.pos.should == 0
    @s.check(/is/).should == nil
    @s.matched.should == nil
  end

  it "treats String as the pattern itself" do
    @s.check("This").should == "This"
    @s.matched.should == "This"
    @s.pos.should == 0
    @s.check(/is/).should == nil
    @s.matched.should == nil
  end

  describe "#[] successive call with a capture group name" do
    context "when #check was called with a Regexp pattern" do
      it "returns matched substring when matching succeeded" do
        @s.check(/(?<a>This)/)
        @s.should.matched?
        @s[:a].should == "This"
      end

      it "returns nil when matching failed" do
        @s.check(/(?<a>2008)/)
        @s.should_not.matched?
        @s[:a].should be_nil
      end
    end

    context "when #check was called with a String pattern" do
      # https://github.com/ruby/strscan/issues/139
      version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
        it "returns nil when matching succeeded" do
          @s.check("This")
          @s.should.matched?
          @s[:a].should be_nil
        end
      end
      version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4"
        it "raises IndexError when matching succeeded" do
          @s.check("This")
          @s.should.matched?
          -> { @s[:a] }.should raise_error(IndexError)
        end
      end

      it "returns nil when matching failed" do
        @s.check("2008")
        @s.should_not.matched?
        @s[:a].should be_nil
      end

      it "returns a matching substring when given Integer index" do
        @s.check("This")
        @s[0].should == "This"
      end

      # https://github.com/ruby/strscan/issues/135
      version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
        it "ignores the previous matching with Regexp" do
          @s.exist?(/(?<a>This)/)
          @s.should.matched?
          @s[:a].should == "This"

          @s.check("This")
          @s.should.matched?
          @s[:a].should be_nil
        end
      end
      version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
        it "ignores the previous matching with Regexp" do
          @s.exist?(/(?<a>This)/)
          @s.should.matched?
          @s[:a].should == "This"

          @s.check("This")
          @s.should.matched?
          -> { @s[:a] }.should raise_error(IndexError)
        end
      end
    end
  end
end
