require_relative '../../spec_helper'
require_relative '../../shared/file/executable'

describe "FileTest.executable?" do
  it_behaves_like :file_executable, :executable?, FileTest
  it_behaves_like :file_executable_missing, :executable?, FileTest
end
