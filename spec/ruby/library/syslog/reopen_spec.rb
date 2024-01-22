require_relative '../../spec_helper'

ruby_version_is ""..."3.4" do

  platform_is_not :windows do
    require_relative 'shared/reopen'
    require 'syslog'

    describe "Syslog.reopen" do
      it_behaves_like :syslog_reopen, :reopen
    end
  end
end
