require_relative "../../../spec_helper"
require_relative 'shared/each'

describe "Zlib::GzipReader#each" do
  it_behaves_like :gzipreader_each, :each
end
