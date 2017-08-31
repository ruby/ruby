platform_is_not :windows do
  require File.expand_path('../../../spec_helper', __FILE__)
  require File.expand_path('../shared/log', __FILE__)
  require 'syslog'

  describe "Syslog.err" do
    it_behaves_like :syslog_log, :err
  end
end
