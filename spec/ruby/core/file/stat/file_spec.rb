require_relative '../../../spec_helper'
require_relative '../../../shared/file/file'
require_relative 'fixtures/classes'

describe "File::Stat#file?" do
  it_behaves_like :file_file, :file?, FileStat
end
