require_relative '../../spec_helper'
require_relative '../../shared/file/blockdev'

describe "FileTest.blockdev?" do
  it_behaves_like :file_blockdev, :blockdev?, FileTest
end
