require_relative '../../spec_helper'

describe "Process::Constants" do
  platform_is :darwin, :netbsd, :freebsd do
    describe "on BSD-like systems" do
      %i[
          WNOHANG
          WUNTRACED
          PRIO_PROCESS
          PRIO_PGRP
          PRIO_USER
          RLIM_INFINITY
          RLIMIT_CPU
          RLIMIT_FSIZE
          RLIMIT_DATA
          RLIMIT_STACK
          RLIMIT_CORE
          RLIMIT_RSS
          RLIMIT_MEMLOCK
          RLIMIT_NPROC
          RLIMIT_NOFILE
      ].each do |const|
        it "defines #{const}" do
          Process.const_defined?(const).should == true
          Process.const_get(const).should.instance_of?(Integer)
        end
      end
    end
  end

  platform_is :darwin do
    describe "on Darwin" do
      %i[
        RLIM_SAVED_MAX
        RLIM_SAVED_CUR
        RLIMIT_AS
      ].each do |const|
        it "defines #{const}" do
          Process.const_defined?(const).should == true
          Process.const_get(const).should.instance_of?(Integer)
        end
      end
    end
  end

  platform_is :linux do
    describe "on Linux" do
      %i[
        WNOHANG
        WUNTRACED
        PRIO_PROCESS
        PRIO_PGRP
        PRIO_USER
        RLIMIT_CPU
        RLIMIT_FSIZE
        RLIMIT_DATA
        RLIMIT_STACK
        RLIMIT_CORE
        RLIMIT_RSS
        RLIMIT_NPROC
        RLIMIT_NOFILE
        RLIMIT_MEMLOCK
        RLIMIT_AS
        RLIM_INFINITY
        RLIM_SAVED_MAX
        RLIM_SAVED_CUR
      ].each do |const|
        it "defines #{const}" do
          Process.const_defined?(const).should == true
          Process.const_get(const).should.instance_of?(Integer)
        end
      end
    end
  end

  platform_is :netbsd, :freebsd do
    describe "on NetBSD and FreeBSD" do
      %i[
        RLIMIT_SBSIZE
        RLIMIT_AS
      ].each do |const|
        it "defines #{const}" do
          Process.const_defined?(const).should == true
          Process.const_get(const).should.instance_of?(Integer)
        end
      end
    end
  end

  platform_is :freebsd do
    describe "on FreeBSD" do
      %i[
        RLIMIT_NPTS
      ].each do |const|
        it "defines #{const}" do
          Process.const_defined?(const).should == true
          Process.const_get(const).should.instance_of?(Integer)
        end
      end
    end
  end

  platform_is :windows do
    describe "on Windows" do
      %i[
          RLIMIT_CPU
          RLIMIT_FSIZE
          RLIMIT_DATA
          RLIMIT_STACK
          RLIMIT_CORE
          RLIMIT_RSS
          RLIMIT_NPROC
          RLIMIT_NOFILE
          RLIMIT_MEMLOCK
          RLIMIT_AS
          RLIM_INFINITY
          RLIM_SAVED_MAX
          RLIM_SAVED_CUR
      ].each do |const|
        it "does not define #{const}" do
          Process.const_defined?(const).should == false
        end
      end
    end
  end
end
