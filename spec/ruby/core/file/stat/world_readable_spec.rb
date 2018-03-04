require_relative '../../../spec_helper'
require_relative '../../../shared/file/world_readable'
require_relative 'fixtures/classes'

describe "File::Stat.world_readable?" do
  it_behaves_like :file_world_readable, :world_readable?, FileStat
end

describe "File::Stat#world_readable?" do
  it "needs to be reviewed for spec completeness"
end
