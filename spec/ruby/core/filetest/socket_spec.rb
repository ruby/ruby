require_relative '../../spec_helper'
require_relative '../../shared/file/socket'

describe "FileTest.socket?" do
  it_behaves_like :file_socket, :socket?, FileTest
end
