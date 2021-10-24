require_relative '../../spec_helper'
require_relative '../../shared/file/world_writable'

describe "File.world_writable?" do
  it_behaves_like :file_world_writable, :world_writable?, File

  it "returns nil if the file does not exist" do
    file = rand.to_s + $$.to_s
    File.should_not.exist?(file)
    File.world_writable?(file).should be_nil
  end
end
