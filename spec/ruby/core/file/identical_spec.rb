require_relative '../../spec_helper'
require_relative '../../shared/file/identical'

describe "File.identical?" do
  it_behaves_like :file_identical, :identical?, File
end
