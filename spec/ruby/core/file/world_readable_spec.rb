require_relative '../../spec_helper'
require_relative '../../shared/file/world_readable'

describe "File.world_readable?" do
  it_behaves_like :file_world_readable, :world_readable?, File

  it "returns nil if the file does not exist" do
    file = rand.to_s + $$.to_s
    File.should_not.exist?(file)
    File.world_readable?(file).should be_nil
  end
end
