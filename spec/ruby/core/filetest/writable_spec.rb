require_relative '../../spec_helper'
require_relative '../../shared/file/writable'

describe "FileTest.writable?" do
  it_behaves_like :file_writable, :writable?, FileTest
  it_behaves_like :file_writable_missing, :writable?, FileTest
end
