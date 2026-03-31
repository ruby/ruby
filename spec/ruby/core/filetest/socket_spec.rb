require_relative '../../spec_helper'
require_relative '../../shared/file/socket'

describe "FileTest.socket?" do
  it_behaves_like :file_socket, :socket?, FileTest

  it "returns false if file does not exist" do
    FileTest.socket?("I_am_a_bogus_file").should == false
  end
end
