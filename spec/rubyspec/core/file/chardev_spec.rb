require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../../../shared/file/chardev', __FILE__)

describe "File.chardev?" do
  it_behaves_like :file_chardev, :chardev?, File
end
