require File.expand_path('../../../spec_helper', __FILE__)
require 'etc'

platform_is_not :windows do
  describe "Etc.sysconf" do
    def should_be_integer_or_nil(value)
      if value.nil?
        value.should == nil
      else
        value.should be_kind_of(Integer)
      end
    end

    it "returns the value of POSIX.1 system configuration variables" do
      Etc.sysconf(Etc::SC_ARG_MAX).should be_kind_of(Integer)
      should_be_integer_or_nil(Etc.sysconf(Etc::SC_CHILD_MAX))
      Etc.sysconf(Etc::SC_HOST_NAME_MAX).should be_kind_of(Integer)
      Etc.sysconf(Etc::SC_LOGIN_NAME_MAX).should be_kind_of(Integer)
      Etc.sysconf(Etc::SC_NGROUPS_MAX).should be_kind_of(Integer)
      Etc.sysconf(Etc::SC_CLK_TCK).should be_kind_of(Integer)
      Etc.sysconf(Etc::SC_OPEN_MAX).should be_kind_of(Integer)
      Etc.sysconf(Etc::SC_PAGESIZE).should be_kind_of(Integer)
      Etc.sysconf(Etc::SC_RE_DUP_MAX).should be_kind_of(Integer)
      Etc.sysconf(Etc::SC_STREAM_MAX).should be_kind_of(Integer)
      should_be_integer_or_nil(Etc.sysconf(Etc::SC_SYMLOOP_MAX))
      Etc.sysconf(Etc::SC_TTY_NAME_MAX).should be_kind_of(Integer)
      should_be_integer_or_nil(Etc.sysconf(Etc::SC_TZNAME_MAX))
      Etc.sysconf(Etc::SC_VERSION).should be_kind_of(Integer)
    end
  end
end
