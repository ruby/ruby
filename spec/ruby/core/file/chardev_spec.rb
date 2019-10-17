require_relative '../../spec_helper'
require_relative '../../shared/file/chardev'

describe "File.chardev?" do
  it_behaves_like :file_chardev, :chardev?, File
end
