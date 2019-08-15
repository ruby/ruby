require_relative '../../../spec_helper'
require_relative '../../../shared/file/executable'
require_relative 'fixtures/classes'

describe "File::Stat#executable?" do
  it_behaves_like :file_executable, :executable?, FileStat
end
