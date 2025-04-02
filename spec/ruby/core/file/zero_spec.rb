require_relative '../../spec_helper'
require_relative '../../shared/file/zero'

describe "File.zero?" do
  it_behaves_like :file_zero, :zero?, File
  it_behaves_like :file_zero_missing, :zero?, File
end
