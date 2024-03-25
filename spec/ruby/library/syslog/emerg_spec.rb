require_relative '../../spec_helper'

platform_is_not :windows do
  require_relative 'shared/log'
  require 'syslog'

  describe "Syslog.emerg" do
    # Some way needs do be found to prevent this spec
    # from causing output on all open terminals. If this
    # is not possible, this spec may need a special guard
    # that only runs when requested.
    quarantine! do
      it_behaves_like :syslog_log, :emerg
    end
  end
end
