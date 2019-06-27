require_relative '../../spec_helper'
require_relative '../../shared/file/pipe'

describe "FileTest.pipe?" do
  it_behaves_like :file_pipe, :pipe?, FileTest
end
