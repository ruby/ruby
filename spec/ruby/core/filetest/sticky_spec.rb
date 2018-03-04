require_relative '../../spec_helper'
require_relative '../../shared/file/sticky'

describe "FileTest.sticky?" do
  it_behaves_like :file_sticky, :sticky?, FileTest
  it_behaves_like :file_sticky_missing, :sticky?, FileTest
end
