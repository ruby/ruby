require_relative '../../spec_helper'
require_relative 'shared/filename'

describe "ARGF.filename" do
  it_behaves_like :argf_filename, :filename
end
