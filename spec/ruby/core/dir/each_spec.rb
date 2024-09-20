require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/closed'

describe "Dir#each" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  before :each do
    @dir = Dir.open DirSpecs.mock_dir
  end

  after :each do
    @dir.close
  end

  it "yields each directory entry in succession" do
    a = []
    @dir.each {|dir| a << dir}

    a.sort.should == DirSpecs.expected_paths
  end

  it "returns the directory which remains open" do
    # an FS does not necessarily impose order
    ls = Dir.entries(DirSpecs.mock_dir)
    @dir.each {}.should == @dir
    @dir.read.should == nil
    @dir.rewind
    ls.should include(@dir.read)
  end

  it "returns the same result when called repeatedly" do
    a = []
    @dir.each {|dir| a << dir}

    b = []
    @dir.each {|dir| b << dir}

    a.sort.should == b.sort
    a.sort.should == DirSpecs.expected_paths
  end

  describe "when no block is given" do
    it "returns an Enumerator" do
      @dir.each.should be_an_instance_of(Enumerator)
      @dir.each.to_a.sort.should == DirSpecs.expected_paths
    end

    describe "returned Enumerator" do
      describe "size" do
        it "should return nil" do
          @dir.each.size.should == nil
        end
      end
    end
  end
end

describe "Dir#each" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it_behaves_like :dir_closed, :each
end
