require_relative '../../spec_helper'
require_relative 'fixtures/common'

ruby_version_is "2.5" do
  describe "Dir.each_child" do
    before :all do
      DirSpecs.create_mock_dirs
    end

    after :all do
      DirSpecs.delete_mock_dirs
    end

    it "yields all names in an existing directory to the provided block" do
      a, b = [], []

      Dir.each_child(DirSpecs.mock_dir) {|f| a << f}
      Dir.each_child("#{DirSpecs.mock_dir}/deeply/nested") {|f| b << f}

      a.sort.should == DirSpecs.expected_paths -  %w[. ..]
      b.sort.should == %w|.dotfile.ext directory|
    end

    it "returns nil when successful" do
      Dir.each_child(DirSpecs.mock_dir) {|f| f}.should == nil
    end

    it "calls #to_path on non-String arguments" do
      p = mock('path')
      p.should_receive(:to_path).and_return(DirSpecs.mock_dir)
      Dir.each_child(p).to_a
    end

    it "raises a SystemCallError if passed a nonexistent directory" do
      lambda { Dir.each_child(DirSpecs.nonexistent) {} }.should raise_error(SystemCallError)
    end

    describe "when no block is given" do
      it "returns an Enumerator" do
        Dir.each_child(DirSpecs.mock_dir).should be_an_instance_of(Enumerator)
        Dir.each_child(DirSpecs.mock_dir).to_a.sort.should == DirSpecs.expected_paths - %w[. ..]
      end

      describe "returned Enumerator" do
        describe "size" do
          it "should return nil" do
            Dir.each_child(DirSpecs.mock_dir).size.should == nil
          end
        end
      end
    end
  end
end
