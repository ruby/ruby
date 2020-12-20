require_relative '../../spec_helper'

describe "Process.euid" do
  it "returns the effective user ID for this process" do
    Process.euid.should be_kind_of(Integer)
  end

  it "also goes by Process::UID.eid" do
    Process::UID.eid.should == Process.euid
  end

  it "also goes by Process::Sys.geteuid" do
    Process::Sys.geteuid.should == Process.euid
  end
end

describe "Process.euid=" do

  platform_is_not :windows do
    it "raises TypeError if not passed an Integer" do
      -> { Process.euid = Object.new }.should raise_error(TypeError)
    end

    as_user do
      it "raises Errno::ERPERM if run by a non superuser trying to set the superuser id" do
        -> { (Process.euid = 0)}.should raise_error(Errno::EPERM)
      end

      it "raises Errno::ERPERM if run by a non superuser trying to set the superuser id from username" do
        -> { Process.euid = "root" }.should raise_error(Errno::EPERM)
      end
    end

    as_superuser do
      describe "if run by a superuser" do
        it "sets the effective user id for the current process if run by a superuser" do
          code = <<-RUBY
            Process.euid = 1
            puts Process.euid
          RUBY
          ruby_exe(code).should == "1\n"
        end
      end
    end
  end
end
