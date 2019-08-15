require_relative '../../spec_helper'
require_relative '../../shared/file/writable'

describe "File.writable?" do
  it_behaves_like :file_writable, :writable?, File
  it_behaves_like :file_writable_missing, :writable?, File
end
