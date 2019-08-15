require_relative '../../spec_helper'
require_relative '../../shared/file/directory'

describe "FileTest.directory?" do
  it_behaves_like :file_directory, :directory?, FileTest
end

describe "FileTest.directory?" do
  it_behaves_like :file_directory_io, :directory?, FileTest
end
