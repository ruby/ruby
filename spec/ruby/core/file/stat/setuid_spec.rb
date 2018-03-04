require_relative '../../../spec_helper'
require_relative '../../../shared/file/setuid'
require_relative 'fixtures/classes'

describe "File::Stat#setuid?" do
  it_behaves_like :file_setuid, :setuid?, FileStat
end

describe "File::Stat#setuid?" do
  it "needs to be reviewed for spec completeness"
end
