require_relative '../../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'spec_helper'
  require_relative 'shared/last_response_code'
  require_relative 'fixtures/server'

  describe "Net::FTP#lastresp" do
    it_behaves_like :net_ftp_last_response_code, :lastresp
  end
end
