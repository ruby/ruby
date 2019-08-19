require_relative '../../../spec_helper'
require_relative '../../../shared/file/executable_real'
require_relative 'fixtures/classes'

describe "File::Stat#executable_real?" do
  it_behaves_like :file_executable_real, :executable_real?, FileStat
end
