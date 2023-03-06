require_relative '../../spec_helper'
require 'etc'

platform_is_not :windows do
  describe "Etc.sysconf" do
    %w[
      SC_ARG_MAX SC_CHILD_MAX SC_HOST_NAME_MAX SC_LOGIN_NAME_MAX SC_NGROUPS_MAX
      SC_CLK_TCK SC_OPEN_MAX SC_PAGESIZE SC_RE_DUP_MAX SC_STREAM_MAX
      SC_SYMLOOP_MAX SC_TTY_NAME_MAX SC_TZNAME_MAX SC_VERSION
    ].each do |const|
      it "returns the value of POSIX.1 system configuration variable #{const}" do
        var = Etc.const_get(const)
        value = Etc.sysconf(var)
        if value.nil?
          value.should == nil
        else
          value.should be_kind_of(Integer)
        end
      end
    end
  end
end
