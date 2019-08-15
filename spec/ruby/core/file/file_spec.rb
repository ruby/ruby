require_relative '../../spec_helper'
require_relative '../../shared/file/file'

describe "File" do
  it "includes Enumerable" do
    File.include?(Enumerable).should == true
  end

  it "includes File::Constants" do
    File.include?(File::Constants).should == true
  end
end

describe "File.file?" do
  it_behaves_like :file_file, :file?, File
end
