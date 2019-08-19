require_relative '../../spec_helper'
require_relative '../../shared/file/exist'

describe "File.exist?" do
  it_behaves_like :file_exist, :exist?, File
end
