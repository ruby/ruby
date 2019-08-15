require_relative '../../spec_helper'
require_relative 'shared/unlink'

describe "File.delete" do
  it_behaves_like :file_unlink, :delete
end
