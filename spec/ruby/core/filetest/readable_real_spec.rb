require_relative '../../spec_helper'
require_relative '../../shared/file/readable_real'

describe "FileTest.readable_real?" do
  it_behaves_like :file_readable_real, :readable_real?, FileTest
  it_behaves_like :file_readable_real_missing, :readable_real?, FileTest
end
