describe :dir_pos_set, shared: true do
  before :each do
    @dir = Dir.open DirSpecs.mock_dir
  end

  after :each do
    @dir.close
  end

  # NOTE: #seek/#pos= to a position not returned by #tell/#pos is undefined
  # and should not be spec'd.

  it "moves the read position to a previously obtained position" do
    pos = @dir.pos
    a   = @dir.read
    b   = @dir.read
    @dir.send @method, pos
    c   = @dir.read

    a.should_not == b
    b.should_not == c
    c.should == a
  end
end
