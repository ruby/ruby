require_relative '../../spec_helper'
require_relative '../../shared/file/zero'

describe "FileTest.empty?" do
  it_behaves_like :file_zero, :empty?, FileTest
  it_behaves_like :file_zero_missing, :empty?, FileTest
end
