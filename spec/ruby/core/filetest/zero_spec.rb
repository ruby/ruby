require_relative '../../spec_helper'
require_relative '../../shared/file/zero'

describe "FileTest.zero?" do
  it_behaves_like :file_zero, :zero?, FileTest
  it_behaves_like :file_zero_missing, :zero?, FileTest
end
