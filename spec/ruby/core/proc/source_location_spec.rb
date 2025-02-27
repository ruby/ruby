require_relative '../../spec_helper'
require_relative 'fixtures/source_location'

describe "Proc#source_location" do
  before :each do
    @proc = ProcSpecs::SourceLocation.my_proc
    @lambda = ProcSpecs::SourceLocation.my_lambda
    @proc_new = ProcSpecs::SourceLocation.my_proc_new
    @method = ProcSpecs::SourceLocation.my_method
  end

  it "returns an Array" do
    @proc.source_location.should be_an_instance_of(Array)
    @proc_new.source_location.should be_an_instance_of(Array)
    @lambda.source_location.should be_an_instance_of(Array)
    @method.source_location.should be_an_instance_of(Array)
  end

  it "sets the first value to the path of the file in which the proc was defined" do
    file = @proc.source_location[0]
    file.should be_an_instance_of(String)
    file.should == File.realpath('fixtures/source_location.rb', __dir__)

    file = @proc_new.source_location[0]
    file.should be_an_instance_of(String)
    file.should == File.realpath('fixtures/source_location.rb', __dir__)

    file = @lambda.source_location[0]
    file.should be_an_instance_of(String)
    file.should == File.realpath('fixtures/source_location.rb', __dir__)

    file = @method.source_location[0]
    file.should be_an_instance_of(String)
    file.should == File.realpath('fixtures/source_location.rb', __dir__)
  end

  it "sets the second value to an Integer representing the line on which the proc was defined" do
    line = @proc.source_location[1]
    line.should be_an_instance_of(Integer)
    line.should == 4

    line = @proc_new.source_location[1]
    line.should be_an_instance_of(Integer)
    line.should == 12

    line = @lambda.source_location[1]
    line.should be_an_instance_of(Integer)
    line.should == 8

    line = @method.source_location[1]
    line.should be_an_instance_of(Integer)
    line.should == 15
  end

  it "works even if the proc was created on the same line" do
    ruby_version_is(""..."3.5") do
      proc { true }.source_location.should == [__FILE__, __LINE__]
      Proc.new { true }.source_location.should == [__FILE__, __LINE__]
      -> { true }.source_location.should == [__FILE__, __LINE__]
    end
    ruby_version_is("3.5") do
      proc { true }.source_location.should == [__FILE__, __LINE__, 11, __LINE__, 19]
      Proc.new { true }.source_location.should == [__FILE__, __LINE__, 15, __LINE__, 23]
      -> { true }.source_location.should == [__FILE__, __LINE__, 8, __LINE__, 17]
    end
  end

  it "returns the first line of a multi-line proc (i.e. the line containing 'proc do')" do
    ProcSpecs::SourceLocation.my_multiline_proc.source_location[1].should == 20
    ProcSpecs::SourceLocation.my_multiline_proc_new.source_location[1].should == 34
    ProcSpecs::SourceLocation.my_multiline_lambda.source_location[1].should == 27
  end

  it "returns the location of the proc's body; not necessarily the proc itself" do
    ProcSpecs::SourceLocation.my_detached_proc.source_location[1].should == 41
    ProcSpecs::SourceLocation.my_detached_proc_new.source_location[1].should == 51
    ProcSpecs::SourceLocation.my_detached_lambda.source_location[1].should == 46
  end

  it "returns the same value for a proc-ified method as the method reports" do
    method = ProcSpecs::SourceLocation.method(:my_proc)
    proc = method.to_proc

    method.source_location.should == proc.source_location
  end

  it "returns nil for a core method that has been proc-ified" do
    method = [].method(:<<)
    proc = method.to_proc

    proc.source_location.should == nil
  end

  it "works for eval with a given line" do
    proc = eval('-> {}', nil, "foo", 100)
    location = proc.source_location
    ruby_version_is(""..."3.5") do
      location.should == ["foo", 100]
    end
    ruby_version_is("3.5") do
      location.should == ["foo", 100, 2, 100, 5]
    end
  end
end
