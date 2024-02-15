require_relative '../../spec_helper'
require_relative 'spec_helper'
require_relative 'fixtures/server'
require_relative 'shared/puttextfile'

describe "Net::FTP#puttextfile" do
  it_behaves_like :net_ftp_puttextfile, :puttextfile
end
