require_relative '../../spec_helper'
require_relative 'shared/read'

describe "File.read" do
  it_behaves_like :file_read_directory, :read, File
end
