require_relative '../../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'spec_helper'
  require_relative 'fixtures/server'
  require_relative 'shared/puttextfile'
  require_relative 'shared/putbinaryfile'

  describe "Net::FTP#put (binary mode)" do
    before :each do
      @binary_mode = true
    end

    it_behaves_like :net_ftp_putbinaryfile, :put
  end

  describe "Net::FTP#put (text mode)" do
    before :each do
      @binary_mode = false
    end

    it_behaves_like :net_ftp_puttextfile, :put
  end
end
