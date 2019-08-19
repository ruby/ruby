require_relative '../../spec_helper'
require_relative '../../shared/file/executable'

describe "File.executable?" do
  it_behaves_like :file_executable, :executable?, File
  it_behaves_like :file_executable_missing, :executable?, File
end
