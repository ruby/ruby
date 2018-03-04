require_relative '../../spec_helper'
require_relative '../../shared/file/exist'

describe "FileTest.exists?" do
  it_behaves_like :file_exist, :exists?, FileTest
end
