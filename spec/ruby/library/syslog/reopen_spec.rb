require_relative '../../spec_helper'

platform_is_not :windows do
  require_relative 'shared/reopen'
  require 'syslog'

  describe "Syslog.reopen" do
    it_behaves_like :syslog_reopen, :reopen
  end
end
