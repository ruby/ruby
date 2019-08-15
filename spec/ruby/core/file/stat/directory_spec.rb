require_relative '../../../spec_helper'
require_relative '../../../shared/file/directory'
require_relative 'fixtures/classes'

describe "File::Stat#directory?" do
  it_behaves_like :file_directory, :directory?, FileStat
end
