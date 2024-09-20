require_relative '../../spec_helper'
require_relative 'spec_helper'
require_relative 'fixtures/server'
require_relative 'shared/gettextfile'
require_relative 'shared/getbinaryfile'

describe "Net::FTP#get (binary mode)" do
  before :each do
    @binary_mode = true
  end

  it_behaves_like :net_ftp_getbinaryfile, :get
end

describe "Net::FTP#get (text mode)" do
  before :each do
    @binary_mode = false
  end

  it_behaves_like :net_ftp_gettextfile, :get
end
