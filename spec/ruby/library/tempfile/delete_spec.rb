require_relative '../../spec_helper'
require 'tempfile'

describe "Tempfile#delete" do
  before :each do
    @tempfile = Tempfile.new("specs")
  end

  it "unlinks self" do
    @tempfile.close
    path = @tempfile.path
    @tempfile.delete
    File.should_not.exist?(path)
  end
end
