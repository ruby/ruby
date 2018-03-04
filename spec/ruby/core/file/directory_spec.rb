require_relative '../../spec_helper'
require_relative '../../shared/file/directory'

describe "File.directory?" do
  it_behaves_like :file_directory, :directory?, File
end

describe "File.directory?" do
  it_behaves_like :file_directory_io, :directory?, File
end
