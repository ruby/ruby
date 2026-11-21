require_relative '../../spec_helper'

describe "File#to_path" do
  before :each do
    @path = tmp("file_to_path")
    @name = File.basename(@path)
    touch @path
  end

  after :each do
    @file.close if @file and !@file.closed?
    rm_r @path
  end

  it "returns a String" do
    @file = File.new @path
    @file.to_path.should.instance_of?(String)
  end

  it "returns a different String on every call" do
    @file = File.new @path
    path1 = @file.to_path
    path2 = @file.to_path
    path1.should == path2
    path1.should_not.equal?(path2)
  end

  it "returns a mutable String" do
    @file = File.new @path.dup.freeze
    path = @file.to_path
    path.should == @path
    path.should_not.frozen?
    path << "test"
    @file.to_path.should == @path
  end

  it "calls to_str on argument and returns exact value" do
    path = mock('path')
    path.should_receive(:to_str).and_return(@path)
    @file = File.new path
    @file.to_path.should == @path
  end

  it "does not normalise the path it returns" do
    Dir.chdir(tmp("")) do
      unorm = "./#{@name}"
      @file = File.new unorm
      @file.to_path.should == unorm
    end
  end

  it "does not canonicalize the path it returns" do
    dir = File.basename tmp("")
    path = "#{tmp("")}../#{dir}/#{@name}"
    @file = File.new path
    @file.to_path.should == path
  end

  it "does not absolute-ise the path it returns" do
    Dir.chdir(tmp("")) do
      @file = File.new @name
      @file.to_path.should == @name
    end
  end

  it "preserves the encoding of the path" do
    path = @path.force_encoding("euc-jp")
    @file = File.new path
    @file.to_path.encoding.should == Encoding.find("euc-jp")
  end

  platform_is :linux do
    guard -> { defined?(File::TMPFILE) } do
      before :each do
        @dir = tmp("tmpfilespec")
        mkdir_p @dir
      end

      after :each do
        rm_r @dir
      end
    end
  end
end
