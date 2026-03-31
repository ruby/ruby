require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#exist?" do
  before do
    @s = StringScanner.new("This is a test")
  end

  it "returns distance in bytes between the current position and the end of the matched substring" do
    @s.exist?(/s/).should == 4
    @s.scan(/This is/)
    @s.exist?(/s/).should == 6
  end

  it "returns 0 if the pattern is empty" do
    @s.exist?(//).should == 0
  end

  it "returns nil if the pattern isn't found in the string" do
    @s.exist?(/S/).should == nil
    @s.scan(/This is/)
    @s.exist?(/i/).should == nil
  end

  it "does not modify the current position" do
    @s.pos.should == 0
    @s.exist?(/s/).should == 4
    @s.pos.should == 0
  end

  version_is StringScanner::Version, ""..."3.1.1" do # ruby_version_is ""..."3.4"
    it "raises TypeError if given a String" do
      -> {
        @s.exist?('T')
      }.should raise_error(TypeError, 'wrong argument type String (expected Regexp)')
    end
  end

  version_is StringScanner::Version, "3.1.1" do # ruby_version_is "3.4"
    it "searches a substring in the rest part of a string if given a String" do
      @s.exist?('a').should == 9
    end

    it "returns nil if the pattern isn't found in the string" do
      @s.exist?("S").should == nil
    end
  end

  describe "#[] successive call with a capture group name" do
    context "when #exist? was called with a Regexp pattern" do
      it "returns matched substring when matching succeeded" do
        @s.exist?(/(?<a>This)/)
        @s.should.matched?
        @s[:a].should == "This"
      end

      it "returns nil when matching failed" do
        @s.exist?(/(?<a>2008)/)
        @s.should_not.matched?
        @s[:a].should be_nil
      end
    end

    version_is StringScanner::Version, "3.1.1" do # ruby_version_is "3.4"
      context "when #exist? was called with a String pattern" do
        # https://github.com/ruby/strscan/issues/139
        version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
          it "returns nil when matching succeeded" do
            @s.exist?("This")
            @s.should.matched?
            @s[:a].should be_nil
          end
        end
        version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.3"
          it "raises IndexError when matching succeeded" do
            @s.exist?("This")
            @s.should.matched?
            -> { @s[:a] }.should raise_error(IndexError)
          end
        end

        it "returns nil when matching failed" do
          @s.exist?("2008")
          @s.should_not.matched?
          @s[:a].should be_nil
        end

        it "returns a matching substring when given Integer index" do
          @s.exist?("This")
          @s[0].should == "This"
        end

        # https://github.com/ruby/strscan/issues/135
        version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
          it "ignores the previous matching with Regexp" do
            @s.exist?(/(?<a>This)/)
            @s.should.matched?
            @s[:a].should == "This"

            @s.exist?("This")
            @s.should.matched?
            @s[:a].should be_nil
          end
        end
        version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
          it "ignores the previous matching with Regexp" do
            @s.exist?(/(?<a>This)/)
            @s.should.matched?
            @s[:a].should == "This"

            @s.exist?("This")
            @s.should.matched?
            -> { @s[:a] }.should raise_error(IndexError)
          end
        end
      end
    end
  end
end
