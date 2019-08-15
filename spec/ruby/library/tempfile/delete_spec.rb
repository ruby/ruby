require_relative '../../spec_helper'
require_relative 'shared/unlink'
require 'tempfile'

describe "Tempfile#delete" do
  it_behaves_like :tempfile_unlink, :delete
end
