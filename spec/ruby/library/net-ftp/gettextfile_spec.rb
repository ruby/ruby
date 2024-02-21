require_relative '../../spec_helper'
require_relative 'spec_helper'
require_relative 'fixtures/server'
require_relative 'shared/gettextfile'

describe "Net::FTP#gettextfile" do
  it_behaves_like :net_ftp_gettextfile, :gettextfile
end
