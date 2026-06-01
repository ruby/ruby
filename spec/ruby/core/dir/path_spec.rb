require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir#path" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it "returns the path that was supplied to .new or .open" do
    dir = Dir.open DirSpecs.mock_dir
    begin
      dir.path.should == DirSpecs.mock_dir
    ensure
      dir.close rescue nil
    end
  end

  it "returns the path even when called on a closed Dir instance" do
    dir = Dir.open DirSpecs.mock_dir
    dir.close
    dir.path.should == DirSpecs.mock_dir
  end

  it "returns a String with the same encoding as the argument to .open" do
    path = DirSpecs.mock_dir.force_encoding Encoding::IBM866
    dir = Dir.open path
    begin
      dir.path.encoding.should.equal?(Encoding::IBM866)
    ensure
      dir.close
    end
  end
end
