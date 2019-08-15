require_relative '../../spec_helper'
require_relative '../../shared/file/writable_real'

describe "File.writable_real?" do
  it_behaves_like :file_writable_real, :writable_real?, File
  it_behaves_like :file_writable_real_missing, :writable_real?, File
end
