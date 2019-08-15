require_relative '../../../spec_helper'
require_relative '../../../shared/file/blockdev'
require_relative 'fixtures/classes'

describe "File::Stat#blockdev?" do
  it_behaves_like :file_blockdev, :blockdev?, FileStat
end
