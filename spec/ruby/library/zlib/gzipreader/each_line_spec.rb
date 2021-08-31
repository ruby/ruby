require_relative 'shared/each'

describe "Zlib::GzipReader#each_line" do
  it_behaves_like :gzipreader_each, :each_line
end
