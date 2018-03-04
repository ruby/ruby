require_relative '../../spec_helper'
require_relative 'shared/unlink'

describe "File.unlink" do
  it_behaves_like :file_unlink, :unlink
end
