require_relative '../../spec_helper'
require_relative 'shared/path'

describe "File#to_path" do
  it_behaves_like :file_path, :to_path
end
