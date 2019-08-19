require_relative '../../spec_helper'
require_relative 'shared/filename'

describe "ARGF.path" do
  it_behaves_like :argf_filename, :path
end
