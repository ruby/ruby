require_relative '../../../spec_helper'
require_relative '../../../shared/file/socket'
require_relative 'fixtures/classes'

describe "File::Stat#socket?" do
  it_behaves_like :file_socket, :socket?, FileStat
end
