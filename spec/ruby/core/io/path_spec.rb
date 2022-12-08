require_relative '../../spec_helper'

describe "IO#path" do
  ruby_version_is "3.2" do
    it "returns the path of the file associated with the IO object" do
      File.open(tmp("io_path.txt"), "w") do |file|
        IO.new(file.fileno, path: file.path, autoclose: false).path.should == file.path
      end
    end
  end
end
