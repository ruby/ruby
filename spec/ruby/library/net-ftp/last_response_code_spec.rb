require_relative '../../spec_helper'
require_relative 'spec_helper'
require_relative 'shared/last_response_code'
require_relative 'fixtures/server'

describe "Net::FTP#last_response_code" do
  it_behaves_like :net_ftp_last_response_code, :last_response_code
end
