require_relative '../../../spec_helper'
require_relative 'spec_helper'
require_relative 'fixtures/server'
require_relative 'shared/getbinaryfile'

describe "Net::FTP#getbinaryfile" do
  it_behaves_like :net_ftp_getbinaryfile, :getbinaryfile
end
