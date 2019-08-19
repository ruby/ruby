require_relative '../../../spec_helper'
require_relative '../../../shared/file/chardev'
require_relative 'fixtures/classes'

describe "File::Stat#chardev?" do
  it_behaves_like :file_chardev, :chardev?, FileStat
end
