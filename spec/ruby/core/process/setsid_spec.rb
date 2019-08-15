require_relative '../../spec_helper'

describe "Process.setsid" do
  platform_is_not :windows do
    it "establishes this process as a new session and process group leader" do
      sid = Process.getsid

      out = ruby_exe("p Process.getsid; p Process.setsid; p Process.getsid").lines
      out[0].should == "#{sid}\n"
      out[1].should == out[2]
      out[2].should_not == "#{sid}\n"

      sid.should == Process.getsid
    end
  end
end
