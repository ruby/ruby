require_relative "../../spec_helper"

describe "Regexp#captures_count" do
    it "returns zero for an empty regex" do
        //.captures_count.should == 0
    end

    it "returns the number of unnamed capture groups" do
        /a (single) group/.captures_count.should == 1
        /(multiple)(capture)(groups)/.captures_count.should == 3
    end

    it "ignores noncapturing groups" do
        /a (?:noncapturing) group/.captures_count.should == 0
    end

    it "counts named capturing groups" do
        /a (?<named>capturing) group/.captures_count.should == 1
    end

    it "ignores atomic groups" do
        /an (?>atomic) group/.captures_count.should == 0
    end
end
