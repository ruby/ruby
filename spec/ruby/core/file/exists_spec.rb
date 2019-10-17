require_relative '../../spec_helper'
require_relative '../../shared/file/exist'

describe "File.exists?" do
  it_behaves_like :file_exist, :exists?, File
end
