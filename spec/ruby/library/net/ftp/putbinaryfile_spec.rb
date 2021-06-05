require_relative '../../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'spec_helper'
  require_relative 'fixtures/server'
  require_relative 'shared/putbinaryfile'

  describe "Net::FTP#putbinaryfile" do
    it_behaves_like :net_ftp_putbinaryfile, :putbinaryfile
  end
end
