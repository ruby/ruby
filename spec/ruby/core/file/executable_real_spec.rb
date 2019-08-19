require_relative '../../spec_helper'
require_relative '../../shared/file/executable_real'

describe "File.executable_real?" do
  it_behaves_like :file_executable_real, :executable_real?, File
  it_behaves_like :file_executable_real_missing, :executable_real?, File
end
