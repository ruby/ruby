require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/closed'
require_relative 'shared/pos'

describe "Dir#tell" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it_behaves_like :dir_closed, :tell

  before :each do
    @dir = Dir.open DirSpecs.mock_dir
  end

  after :each do
    @dir.close rescue nil
  end

  it "returns an Integer representing the current position in the directory" do
    @dir.tell.should.is_a?(Integer)
    @dir.tell.should.is_a?(Integer)
    @dir.tell.should.is_a?(Integer)
  end

  it "returns a different Integer if moved from previous position" do
    a = @dir.tell
    @dir.read
    b = @dir.tell

    a.should.is_a?(Integer)
    b.should.is_a?(Integer)

    a.should_not == b
  end
end
