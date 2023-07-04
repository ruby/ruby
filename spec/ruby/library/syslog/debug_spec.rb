require_relative '../../spec_helper'

ruby_version_is ""..."3.3" do

  platform_is_not :windows do
    require_relative 'shared/log'
    require 'syslog'

    describe "Syslog.debug" do
      it_behaves_like :syslog_log, :debug
    end
  end
end
