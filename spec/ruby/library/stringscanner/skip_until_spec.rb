require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#skip_until" do
  before do
    @s = StringScanner.new("This is a test")
  end

  it "returns the number of bytes advanced and advances the scan pointer until pattern is matched and consumed" do
    @s.skip_until(/a/).should == 9
    @s.pos.should == 9
  end

  it "sets the last match result" do
    @s.skip_until(/a/)

    @s.pre_match.should == "This is "
    @s.matched.should == "a"
    @s.post_match.should == " test"
  end

  it "returns nil if no match was found" do
    @s.skip_until(/d+/).should == nil
  end

  version_is StringScanner::Version, ""..."3.1.1" do # ruby_version_is ""..."3.4"
    it "raises TypeError if given a String" do
      -> {
        @s.skip_until('T')
      }.should raise_error(TypeError, 'wrong argument type String (expected Regexp)')
    end
  end

  version_is StringScanner::Version, "3.1.1" do # ruby_version_is "3.4"
    it "searches a substring in the rest part of a string if given a String" do
      @s.skip_until("a").should == 9
      @s.pos.should == 9
    end

    # https://github.com/ruby/strscan/issues/131
    version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.1"
      it "sets the last match result if given a String" do
        @s.skip_until("a")

        @s.pre_match.should == ""
        @s.matched.should == "This is a"
        @s.post_match.should == " test"
      end
    end

    version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4"
      it "sets the last match result if given a String" do
        @s.skip_until("a")

        @s.pre_match.should == "This is "
        @s.matched.should == "a"
        @s.post_match.should == " test"
      end
    end
  end

  describe "#[] successive call with a capture group name" do
    context "when #scan_until was called with a Regexp pattern" do
      it "returns matched substring when matching succeeded" do
        @s.skip_until(/(?<a>This)/)
        @s.should.matched?
        @s[:a].should == "This"
      end

      it "returns nil when matching failed" do
        @s.skip_until(/(?<a>2008)/)
        @s.should_not.matched?
        @s[:a].should be_nil
      end
    end

    version_is StringScanner::Version, "3.1.1" do # ruby_version_is "3.4"
      context "when #skip_until was called with a String pattern" do
        # https://github.com/ruby/strscan/issues/139
        version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
          it "returns nil when matching succeeded" do
            @s.skip_until("This")
            @s.should.matched?
            @s[:a].should be_nil
          end
        end
        version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.3"
          it "raises IndexError when matching succeeded" do
            @s.skip_until("This")
            @s.should.matched?
            -> { @s[:a] }.should raise_error(IndexError)
          end
        end

        it "returns nil when matching failed" do
          @s.skip_until("2008")
          @s.should_not.matched?
          @s[:a].should be_nil
        end

        it "returns a matching substring when given Integer index" do
          @s.skip_until("This")
          @s[0].should == "This"
        end

        # https://github.com/ruby/strscan/issues/135
        version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
          it "ignores the previous matching with Regexp" do
            @s.exist?(/(?<a>This)/)
            @s.should.matched?
            @s[:a].should == "This"

            @s.skip_until("This")
            @s.should.matched?
            @s[:a].should be_nil
          end
        end
        version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4"
          it "ignores the previous matching with Regexp" do
            @s.exist?(/(?<a>This)/)
            @s.should.matched?
            @s[:a].should == "This"

            @s.skip_until("This")
            @s.should.matched?
            -> { @s[:a] }.should raise_error(IndexError)
          end
        end
      end
    end
  end
end
