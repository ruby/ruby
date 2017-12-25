require File.expand_path('../../../spec_helper', __FILE__)

platform_is_not :windows do
  require File.expand_path('../shared/log', __FILE__)
  require 'syslog'

  describe "Syslog.debug" do
    it_behaves_like :syslog_log, :debug
  end
end
