require_relative '../../../spec_helper'
require_relative '../../../shared/file/setgid'
require_relative 'fixtures/classes'

describe "File::Stat#setgid?" do
  it_behaves_like :file_setgid, :setgid?, FileStat
end
