require_relative '../../../spec_helper'
require_relative '../../../shared/file/grpowned'
require_relative 'fixtures/classes'

describe "File::Stat#grpowned?" do
  it_behaves_like :file_grpowned, :grpowned?, FileStat
end
