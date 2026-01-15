require_relative '../../spec_helper'
require_relative '../../shared/file/zero'

describe "File.empty?" do
  it_behaves_like :file_zero, :empty?, File
  it_behaves_like :file_zero_missing, :empty?, File
end
