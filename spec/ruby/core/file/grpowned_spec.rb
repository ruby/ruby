require_relative '../../spec_helper'
require_relative '../../shared/file/grpowned'

describe "File.grpowned?" do
  it_behaves_like :file_grpowned, :grpowned?, File

  it "returns false if file the does not exist" do
    File.grpowned?("i_am_a_bogus_file").should == false
  end
end
