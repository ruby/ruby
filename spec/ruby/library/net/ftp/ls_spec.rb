require_relative '../../../spec_helper'
require_relative 'spec_helper'
require_relative 'fixtures/server'
require_relative 'shared/list'

describe "Net::FTP#ls" do
  it_behaves_like :net_ftp_list, :ls
end
