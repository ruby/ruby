require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir#to_path" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it "returns the to_path that was supplied to .new or .open" do
    dir = Dir.open DirSpecs.mock_dir
    begin
      dir.to_path.should == DirSpecs.mock_dir
    ensure
      dir.close rescue nil
    end
  end

  it "returns the to_path even when called on a closed Dir instance" do
    dir = Dir.open DirSpecs.mock_dir
    dir.close
    dir.to_path.should == DirSpecs.mock_dir
  end

  it "returns a String with the same encoding as the argument to .open" do
    to_path = DirSpecs.mock_dir.force_encoding Encoding::IBM866
    dir = Dir.open to_path
    begin
      dir.to_path.encoding.should.equal?(Encoding::IBM866)
    ensure
      dir.close
    end
  end
end
