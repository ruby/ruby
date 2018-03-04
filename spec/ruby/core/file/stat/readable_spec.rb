require_relative '../../../spec_helper'
require_relative '../../../shared/file/readable'
require_relative 'fixtures/classes'

describe "File::Stat#readable?" do
  it_behaves_like :file_readable, :readable?, FileStat
end
