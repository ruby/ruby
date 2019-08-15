require_relative '../../../spec_helper'
require_relative '../../../shared/file/readable_real'
require_relative 'fixtures/classes'

describe "File::Stat#readable_real?" do
  it_behaves_like :file_readable_real, :readable_real?, FileStat
end
