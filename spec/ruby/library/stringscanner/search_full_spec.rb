require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#search_full" do
  before do
    @s = StringScanner.new("This is a test")
  end

  it "returns the number of bytes advanced" do
    orig_pos = @s.pos
    @s.search_full(/This/, false, false).should == 4
    @s.pos.should == orig_pos
  end

  it "returns the number of bytes advanced and advances the scan pointer if the second argument is true" do
    @s.search_full(/This/, true, false).should == 4
    @s.pos.should == 4
  end

  it "returns the matched string if the third argument is true" do
    orig_pos = @s.pos
    @s.search_full(/This/, false, true).should == "This"
    @s.pos.should == orig_pos
  end

  it "returns the matched string if the third argument is true and advances the scan pointer if the second argument is true" do
    @s.search_full(/This/, true, true).should == "This"
    @s.pos.should == 4
  end

  it "sets the last match result" do
    @s.search_full(/is a/, false, false)

    @s.pre_match.should == "This "
    @s.matched.should == "is a"
    @s.post_match.should == " test"
  end

  version_is StringScanner::Version, ""..."3.1.1" do # ruby_version_is ""..."3.4"
    it "raises TypeError if given a String" do
      -> {
        @s.search_full('T', true, true)
      }.should raise_error(TypeError, 'wrong argument type String (expected Regexp)')
    end
  end

  version_is StringScanner::Version, "3.1.1" do # ruby_version_is "3.4"
    it "searches a substring in the rest part of a string if given a String" do
      @s.search_full("is a", false, false).should == 9
    end

    # https://github.com/ruby/strscan/issues/131
    version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.1"
      it "sets the last match result if given a String" do
        @s.search_full("is a", false, false)

        @s.pre_match.should == ""
        @s.matched.should == "This is a"
        @s.post_match.should == " test"
      end
    end

    version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4"
      it "sets the last match result if given a String" do
        @s.search_full("is a", false, false)

        @s.pre_match.should == "This "
        @s.matched.should == "is a"
        @s.post_match.should == " test"
      end
    end
  end

  describe "#[] successive call with a capture group name" do
    context "when #search_full was called with a Regexp pattern" do
      it "returns matched substring when matching succeeded" do
        @s.search_full(/(?<a>This)/, false, false)
        @s.should.matched?
        @s[:a].should == "This"
      end

      it "returns nil when matching failed" do
        @s.search_full(/(?<a>2008)/, false, false)
        @s.should_not.matched?
        @s[:a].should be_nil
      end
    end

    version_is StringScanner::Version, "3.1.1" do # ruby_version_is "3.4"
      context "when #search_full was called with a String pattern" do
        # https://github.com/ruby/strscan/issues/139
        version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
          it "returns nil when matching succeeded" do
            @s.search_full("This", false, false)
            @s.should.matched?
            @s[:a].should be_nil
          end
        end
        version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.3"
          it "raises IndexError when matching succeeded" do
            @s.search_full("This", false, false)
            @s.should.matched?
            -> { @s[:a] }.should raise_error(IndexError)
          end
        end

        it "returns nil when matching failed" do
          @s.search_full("2008", false, false)
          @s.should_not.matched?
          @s[:a].should be_nil
        end

        it "returns a matching substring when given Integer index" do
          @s.search_full("This", false, false)
          @s[0].should == "This"
        end

        # https://github.com/ruby/strscan/issues/135
        version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4"
          it "ignores the previous matching with Regexp" do
            @s.exist?(/(?<a>This)/)
            @s.should.matched?
            @s[:a].should == "This"

            @s.search_full("This", false, false)
            @s.should.matched?
            -> { @s[:a] }.should raise_error(IndexError)
          end
        end
      end
    end
  end
end
