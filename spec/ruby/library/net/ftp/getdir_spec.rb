require_relative '../../../spec_helper'
require_relative 'spec_helper'
require_relative 'shared/pwd'

describe "Net::FTP#getdir" do
  it_behaves_like :net_ftp_pwd, :getdir
end
