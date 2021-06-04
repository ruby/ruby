require_relative '../../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'spec_helper'
  require_relative 'shared/pwd'

  describe "Net::FTP#getdir" do
    it_behaves_like :net_ftp_pwd, :getdir
  end
end
