require_relative '../../../spec_helper'
require_relative '../../../shared/file/size'
require_relative 'fixtures/classes'

describe "File::Stat.size?" do
  it_behaves_like :file_size,                     :size?, FileStat
  it_behaves_like :file_size_nil_when_empty,      :size?, FileStat
end

describe "File::Stat.size" do
  it_behaves_like :file_size,                     :size,  FileStat
  it_behaves_like :file_size_0_when_empty,        :size,  FileStat
end

describe "File::Stat#size" do
  it "needs to be reviewed for spec completeness"
end

describe "File::Stat#size?" do
  it "needs to be reviewed for spec completeness"
end
