require_relative '../../../spec_helper'
require_relative '../../../shared/file/zero'
require_relative 'fixtures/classes'

describe "File::Stat#zero?" do
  it_behaves_like :file_zero, :zero?, FileStat
end
