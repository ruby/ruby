require_relative '../../spec_helper'
require_relative '../../shared/file/identical'

describe "FileTest.identical?" do
  it_behaves_like :file_identical, :identical?, FileTest
end
