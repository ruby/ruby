require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Process.uid" do
  platform_is_not :windows do
    it "returns the correct uid for the user executing this process" do
      current_uid_according_to_unix = `id -ur`.to_i
      Process.uid.should == current_uid_according_to_unix
    end
  end

  it "also goes by Process::UID.rid" do
    Process::UID.rid.should == Process.uid
  end

  it "also goes by Process::Sys.getuid" do
    Process::Sys.getuid.should == Process.uid
  end
end

describe "Process.uid=" do
  platform_is_not :windows do
    it "raises TypeError if not passed an Integer" do
      -> { Process.uid = Object.new }.should.raise(TypeError)
    end

    as_user do
      it "raises Errno::ERPERM if run by a non privileged user trying to set the superuser id" do
        skip "Codex sandbox returns EINVAL instead of EPERM for uid/gid permission changes" if ProcessSpecs.codex_sandbox?
        -> { (Process.uid = 0)}.should.raise(Errno::EPERM)
      end

      it "raises Errno::ERPERM if run by a non privileged user trying to set the superuser id from username" do
        skip "Codex sandbox returns EINVAL instead of EPERM for uid/gid permission changes" if ProcessSpecs.codex_sandbox?
        -> { Process.uid = "root" }.should.raise(Errno::EPERM)
      end
    end

    as_superuser do
      describe "if run by a superuser" do
        it "sets the real user id for the current process" do
          code = <<-RUBY
            Process.uid = 1
            puts Process.uid
          RUBY
          ruby_exe(code).should == "1\n"
        end

        it "sets the real user id if preceded by Process.euid=id" do
          code = <<-RUBY
            Process.euid = 1
            Process.uid = 1
            puts Process.uid
          RUBY
          ruby_exe(code).should == "1\n"
        end
      end
    end
  end
end
