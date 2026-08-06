require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Process.egid" do
  it "returns the effective group ID for this process" do
    Process.egid.should.is_a?(Integer)
  end

  it "also goes by Process::GID.eid" do
    Process::GID.eid.should == Process.egid
  end

  it "also goes by Process::Sys.getegid" do
    Process::Sys.getegid.should == Process.egid
  end
end

describe "Process.egid=" do

  platform_is_not :windows do
    it "raises TypeError if not passed an Integer or String" do
      -> { Process.egid = Object.new }.should.raise(TypeError)
    end

    it "sets the effective group id to its own gid if given the username corresponding to its own gid" do
      raise unless Process.gid == Process.egid

      require "etc"
      group = Etc.getgrgid(Process.gid).name

      Process.egid = group
      Process.egid.should == Process.gid
    end

    as_user do
      it "raises Errno::ERPERM if run by a non superuser trying to set the root group id" do
        skip "Codex sandbox returns EINVAL instead of EPERM for uid/gid permission changes" if ProcessSpecs.codex_sandbox?
        -> { Process.egid = 0 }.should.raise(Errno::EPERM)
      end

      platform_is :linux do
        it "raises Errno::ERPERM if run by a non superuser trying to set the group id from group name" do
          skip "Codex sandbox returns EINVAL instead of EPERM for uid/gid permission changes" if ProcessSpecs.codex_sandbox?
          -> { Process.egid = "root" }.should.raise(Errno::EPERM)
        end
      end
    end

    as_superuser do
      context "when ran by a superuser" do
        it "sets the effective group id for the current process if run by a superuser" do
          code = <<-RUBY
            Process.egid = 1
            puts Process.egid
          RUBY
          ruby_exe(code).should == "1\n"
        end
      end
    end
  end
end
