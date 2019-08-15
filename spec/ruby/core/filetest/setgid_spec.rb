require_relative '../../spec_helper'
require_relative '../../shared/file/setgid'

describe "FileTest.setgid?" do
  it_behaves_like :file_setgid, :setgid?, FileTest
end
