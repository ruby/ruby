require_relative '../../spec_helper'

ruby_version_is "3.4" do
  describe "MatchData#bytebegin" do
    context "when passed an integer argument" do
      it "returns the byte-based offset of the start of the nth element" do
        match_data = /(.)(.)(\d+)(\d)/.match("THX1138.")
        match_data.bytebegin(0).should == 1
        match_data.bytebegin(2).should == 2
      end

      it "returns nil when the nth match isn't found" do
        match_data = /something is( not)? (right)/.match("something is right")
        match_data.bytebegin(1).should be_nil
      end

      it "returns the byte-based offset for multi-byte strings" do
        match_data = /(.)(.)(\d+)(\d)/.match("TñX1138.")
        match_data.bytebegin(0).should == 1
        match_data.bytebegin(2).should == 3
      end

      not_supported_on :opal do
        it "returns the byte-based offset for multi-byte strings with unicode regexp" do
          match_data = /(.)(.)(\d+)(\d)/u.match("TñX1138.")
          match_data.bytebegin(0).should == 1
          match_data.bytebegin(2).should == 3
        end
      end

      it "tries to convert the passed argument to an Integer using #to_int" do
        obj = mock('to_int')
        obj.should_receive(:to_int).and_return(2)

        match_data = /(.)(.)(\d+)(\d)/.match("THX1138.")
        match_data.bytebegin(obj).should == 2
      end

      it "raises IndexError if index is out of bounds" do
        match_data = /(?<f>foo)(?<b>bar)/.match("foobar")

        -> {
          match_data.bytebegin(-1)
        }.should raise_error(IndexError, "index -1 out of matches")

        -> {
          match_data.bytebegin(3)
        }.should raise_error(IndexError, "index 3 out of matches")
      end
    end

    context "when passed a String argument" do
      it "return the byte-based offset of the start of the named capture" do
        match_data = /(?<a>.)(.)(?<b>\d+)(\d)/.match("THX1138.")
        match_data.bytebegin("a").should == 1
        match_data.bytebegin("b").should == 3
      end

      it "returns the byte-based offset for multi byte strings" do
        match_data = /(?<a>.)(.)(?<b>\d+)(\d)/.match("TñX1138.")
        match_data.bytebegin("a").should == 1
        match_data.bytebegin("b").should == 4
      end

      not_supported_on :opal do
        it "returns the byte-based offset for multi byte strings with unicode regexp" do
          match_data = /(?<a>.)(.)(?<b>\d+)(\d)/u.match("TñX1138.")
          match_data.bytebegin("a").should == 1
          match_data.bytebegin("b").should == 4
        end
      end

      it "returns the byte-based offset for the farthest match when multiple named captures use the same name" do
        match_data = /(?<a>.)(.)(?<a>\d+)(\d)/.match("THX1138.")
        match_data.bytebegin("a").should == 3
      end

      it "returns the byte-based offset for multi-byte names" do
        match_data = /(?<æ>.)(.)(?<b>\d+)(\d)/.match("THX1138.")
        match_data.bytebegin("æ").should == 1
      end

      it "raises IndexError if there is no group with the provided name" do
        match_data = /(?<f>foo)(?<b>bar)/.match("foobar")

        -> {
          match_data.bytebegin("y")
        }.should raise_error(IndexError, "undefined group name reference: y")
      end
    end

    context "when passed a Symbol argument" do
      it "return the byte-based offset of the start of the named capture" do
        match_data = /(?<a>.)(.)(?<b>\d+)(\d)/.match("THX1138.")
        match_data.bytebegin(:a).should == 1
        match_data.bytebegin(:b).should == 3
      end

      it "returns the byte-based offset for multi byte strings" do
        match_data = /(?<a>.)(.)(?<b>\d+)(\d)/.match("TñX1138.")
        match_data.bytebegin(:a).should == 1
        match_data.bytebegin(:b).should == 4
      end

      not_supported_on :opal do
        it "returns the byte-based offset for multi byte strings with unicode regexp" do
          match_data = /(?<a>.)(.)(?<b>\d+)(\d)/u.match("TñX1138.")
          match_data.bytebegin(:a).should == 1
          match_data.bytebegin(:b).should == 4
        end
      end

      it "returns the byte-based offset for the farthest match when multiple named captures use the same name" do
        match_data = /(?<a>.)(.)(?<a>\d+)(\d)/.match("THX1138.")
        match_data.bytebegin(:a).should == 3
      end

      it "returns the byte-based offset for multi-byte names" do
        match_data = /(?<æ>.)(.)(?<b>\d+)(\d)/.match("THX1138.")
        match_data.bytebegin(:æ).should == 1
      end

      it "raises IndexError if there is no group with the provided name" do
        match_data = /(?<f>foo)(?<b>bar)/.match("foobar")

        -> {
          match_data.bytebegin(:y)
        }.should raise_error(IndexError, "undefined group name reference: y")
      end
    end
  end
end
