require_relative '../../spec_helper'
require_relative '../../shared/file/readable'

describe "FileTest.readable?" do
  it_behaves_like :file_readable, :readable?, FileTest
  it_behaves_like :file_readable_missing, :readable?, FileTest
end
