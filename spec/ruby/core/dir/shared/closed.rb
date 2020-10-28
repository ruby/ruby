describe :dir_closed, shared: true do
  it "raises an IOError when called on a closed Dir instance" do
    -> {
      dir = Dir.open DirSpecs.mock_dir
      dir.close
      dir.send(@method) {}
    }.should raise_error(IOError)
  end
end
