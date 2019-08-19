require_relative '../../spec_helper'
require_relative '../../shared/file/symlink'

describe "FileTest.symlink?" do
  it_behaves_like :file_symlink, :symlink?, FileTest
end

describe "FileTest.symlink?" do
  it_behaves_like :file_symlink_nonexistent, :symlink?, File
end
