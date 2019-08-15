require_relative '../../spec_helper'
require_relative 'shared/fnmatch'

describe "File.fnmatch" do
  it_behaves_like :file_fnmatch, :fnmatch
end

describe "File.fnmatch?" do
  it_behaves_like :file_fnmatch, :fnmatch?
end
