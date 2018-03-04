require_relative '../../../spec_helper'
require_relative '../fixtures/common'
require_relative 'closed'

describe :dir_path, shared: true do
  it "returns the path that was supplied to .new or .open" do
    dir = Dir.open DirSpecs.mock_dir
    begin
      dir.send(@method).should == DirSpecs.mock_dir
    ensure
      dir.close rescue nil
    end
  end

  it "returns the path even when called on a closed Dir instance" do
    dir = Dir.open DirSpecs.mock_dir
    dir.close
    dir.send(@method).should == DirSpecs.mock_dir
  end

  with_feature :encoding do
    it "returns a String with the same encoding as the argument to .open" do
      path = DirSpecs.mock_dir.force_encoding Encoding::IBM866
      dir = Dir.open path
      begin
        dir.send(@method).encoding.should equal(Encoding::IBM866)
      ensure
        dir.close
      end
    end
  end
end
