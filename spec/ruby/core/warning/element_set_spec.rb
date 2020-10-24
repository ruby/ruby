require_relative '../../spec_helper'

ruby_version_is '2.7' do
  describe "Warning.[]=" do
    it "emits and suppresses warnings for :deprecated" do
      ruby_exe('Warning[:deprecated] = true; $; = ""', args: "2>&1").should =~ /is deprecated/
      ruby_exe('Warning[:deprecated] = false; $; = ""', args: "2>&1").should == ""
    end

    it "emits and suppresses warnings for :experimental" do
      ruby_exe('Warning[:experimental] = true; eval("0 in a")', args: "2>&1").should =~ /is experimental/
      ruby_exe('Warning[:experimental] = false; eval("0 in a")', args: "2>&1").should == ""
    end

    it "raises for unknown category" do
      -> { Warning[:noop] = false }.should raise_error(ArgumentError, /unknown category: noop/)
    end
  end
end
