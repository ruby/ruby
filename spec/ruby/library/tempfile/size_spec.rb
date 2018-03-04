require_relative '../../spec_helper'
require_relative 'shared/length'
require 'tempfile'

describe "Tempfile#size" do
  it_behaves_like :tempfile_length, :size
end
