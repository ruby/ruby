require_relative '../../spec_helper'
require_relative '../../shared/file/owned'

describe "FileTest.owned?" do
  it_behaves_like :file_owned, :owned?, FileTest
end
