require_relative '../../../spec_helper'
require_relative '../../../shared/file/world_writable'
require_relative 'fixtures/classes'

describe "File::Stat.world_writable?" do
  it_behaves_like :file_world_writable, :world_writable?, FileStat
end

describe "File::Stat#world_writable?" do
  it "needs to be reviewed for spec completeness"
end
