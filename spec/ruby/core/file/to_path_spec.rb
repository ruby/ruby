require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/path', __FILE__)

describe "File#to_path" do
  it_behaves_like :file_path, :to_path
end
