require_relative '../../spec_helper'
require_relative '../../shared/file/chardev'

describe "FileTest.chardev?" do
  it_behaves_like :file_chardev, :chardev?, FileTest
end
