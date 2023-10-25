require_relative '../../../spec_helper'

ruby_version_is "3.1" do
  describe "Thread::Backtrace.limit" do
    it "returns maximum backtrace length set by --backtrace-limit command-line option" do
      out = ruby_exe("print Thread::Backtrace.limit", options: "--backtrace-limit=2")
      out.should == "2"
    end

    it "returns -1 when --backtrace-limit command-line option is not set" do
      out = ruby_exe("print Thread::Backtrace.limit")
      out.should == "-1"
    end
  end
end
