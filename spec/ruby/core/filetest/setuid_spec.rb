require_relative '../../spec_helper'
require_relative '../../shared/file/setuid'

describe "FileTest.setuid?" do
  it_behaves_like :file_setuid, :setuid?, FileTest
end

describe "FileTest.setuid?" do
  it "needs to be reviewed for spec completeness"
end
