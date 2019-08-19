require_relative '../../../spec_helper'
require_relative '../../../shared/file/sticky'
require_relative 'fixtures/classes'

describe "File::Stat#sticky?" do
  it_behaves_like :file_sticky, :sticky?, FileStat
end
