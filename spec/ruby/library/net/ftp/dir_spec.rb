require_relative '../../../spec_helper'
require_relative 'spec_helper'
require_relative 'fixtures/server'
require_relative 'shared/list'

describe "Net::FTP#dir" do
  it_behaves_like :net_ftp_list, :dir
end
