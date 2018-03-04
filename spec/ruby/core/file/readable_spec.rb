require_relative '../../spec_helper'
require_relative '../../shared/file/readable'

describe "File.readable?" do
  it_behaves_like :file_readable, :readable?, File
  it_behaves_like :file_readable_missing, :readable?, File
end
