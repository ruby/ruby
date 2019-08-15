require_relative '../../spec_helper'
require_relative '../../shared/file/blockdev'

describe "File.blockdev?" do
  it_behaves_like :file_blockdev, :blockdev?, File
end
