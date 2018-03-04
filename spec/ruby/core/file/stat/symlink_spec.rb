require_relative '../../../spec_helper'
require_relative '../../../shared/file/symlink'
require_relative 'fixtures/classes'

describe "File::Stat#symlink?" do
  it_behaves_like :file_symlink, :symlink?, FileStat
end
