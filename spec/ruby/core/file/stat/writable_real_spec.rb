require_relative '../../../spec_helper'
require_relative '../../../shared/file/writable_real'
require_relative 'fixtures/classes'

describe "File::Stat#writable_real?" do
  it_behaves_like :file_writable_real, :writable_real?, FileStat
end
