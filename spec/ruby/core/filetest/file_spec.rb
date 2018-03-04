require_relative '../../spec_helper'
require_relative '../../shared/file/file'

describe "File.file?" do
  it_behaves_like :file_file, :file?, File
end

describe "FileTest.file?" do
  it "needs to be reviewed for spec completeness"
end
