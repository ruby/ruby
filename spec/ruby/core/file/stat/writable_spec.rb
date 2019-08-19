require_relative '../../../spec_helper'
require_relative '../../../shared/file/writable'
require_relative 'fixtures/classes'

describe "File::Stat#writable?" do
  it_behaves_like :file_writable, :writable?, FileStat
end
