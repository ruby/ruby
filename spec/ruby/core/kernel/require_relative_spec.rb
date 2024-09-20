require_relative '../../spec_helper'
require_relative '../../fixtures/code_loading'

describe "Kernel#require_relative with a relative path" do
  before :each do
    CodeLoadingSpecs.spec_setup
    @dir = "../../fixtures/code"
    @abs_dir = File.realpath(@dir, __dir__)
    @path = "#{@dir}/load_fixture.rb"
    @abs_path = File.realpath(@path, __dir__)
  end

  after :each do
    CodeLoadingSpecs.spec_cleanup
  end

  platform_is_not :windows do
    describe "when file is a symlink" do
      before :each do
        @link = tmp("symlink.rb", false)
        @real_path = "#{@abs_dir}/symlink/symlink1.rb"
        File.symlink(@real_path, @link)
      end

      after :each do
        rm_r @link
      end

      it "loads a path relative to current file" do
        require_relative(@link).should be_true
        ScratchPad.recorded.should == [:loaded]
      end
    end
  end

  it "loads a path relative to the current file" do
    require_relative(@path).should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  describe "in an #instance_eval with a" do

    it "synthetic file base name loads a file base name relative to the working directory" do
      Dir.chdir @abs_dir do
        Object.new.instance_eval("require_relative(#{File.basename(@path).inspect})", "foo.rb").should be_true
      end
      ScratchPad.recorded.should == [:loaded]
    end

    it "synthetic file path loads a relative path relative to the working directory plus the directory of the synthetic path" do
      Dir.chdir @abs_dir do
        Object.new.instance_eval("require_relative(File.join('..', #{File.basename(@path).inspect}))", "bar/foo.rb").should be_true
      end
      ScratchPad.recorded.should == [:loaded]
    end

    platform_is_not :windows do
      it "synthetic relative file path with a Windows path separator specified loads a relative path relative to the working directory" do
        Dir.chdir @abs_dir do
          Object.new.instance_eval("require_relative(#{File.basename(@path).inspect})", "bar\\foo.rb").should be_true
        end
        ScratchPad.recorded.should == [:loaded]
      end
    end

    it "absolute file path loads a path relative to the absolute path" do
      Object.new.instance_eval("require_relative(#{@path.inspect})", __FILE__).should be_true
      ScratchPad.recorded.should == [:loaded]
    end

    it "absolute file path loads a path relative to the root directory" do
      root = @abs_path
      until File.dirname(root) == root
        root = File.dirname(root)
      end
      root_relative = @abs_path[root.size..-1]
      Object.new.instance_eval("require_relative(#{root_relative.inspect})", "/").should be_true
      ScratchPad.recorded.should == [:loaded]
    end

  end

  it "loads a file defining many methods" do
    require_relative("#{@dir}/methods_fixture.rb").should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "raises a LoadError if the file does not exist" do
    -> { require_relative("#{@dir}/nonexistent.rb") }.should raise_error(LoadError)
    ScratchPad.recorded.should == []
  end

  it "raises a LoadError that includes the missing path" do
    missing_path = "#{@dir}/nonexistent.rb"
    expanded_missing_path = File.expand_path(missing_path, __dir__)
    -> { require_relative(missing_path) }.should raise_error(LoadError) { |e|
      e.message.should include(expanded_missing_path)
      e.path.should == expanded_missing_path
    }
    ScratchPad.recorded.should == []
  end

  it "raises a LoadError if basepath does not exist" do
    -> { eval("require_relative('#{@dir}/nonexistent.rb')") }.should raise_error(LoadError)
  end

  it "stores the missing path in a LoadError object" do
    path = "#{@dir}/nonexistent.rb"

    -> {
      require_relative(path)
    }.should(raise_error(LoadError) { |e|
      e.path.should == File.expand_path(path, @abs_dir)
    })
  end

  it "calls #to_str on non-String objects" do
    name = mock("load_fixture.rb mock")
    name.should_receive(:to_str).and_return(@path)
    require_relative(name).should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "raises a TypeError if argument does not respond to #to_str" do
    -> { require_relative(nil) }.should raise_error(TypeError)
    -> { require_relative(42) }.should raise_error(TypeError)
    -> {
      require_relative([@path,@path])
    }.should raise_error(TypeError)
  end

  it "raises a TypeError if passed an object that has #to_s but not #to_str" do
    name = mock("load_fixture.rb mock")
    name.stub!(:to_s).and_return(@path)
    -> { require_relative(name) }.should raise_error(TypeError)
  end

  it "raises a TypeError if #to_str does not return a String" do
    name = mock("#to_str returns nil")
    name.should_receive(:to_str).at_least(1).times.and_return(nil)
    -> { require_relative(name) }.should raise_error(TypeError)
  end

  it "calls #to_path on non-String objects" do
    name = mock("load_fixture.rb mock")
    name.should_receive(:to_path).and_return(@path)
    require_relative(name).should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "calls #to_str on non-String objects returned by #to_path" do
    name = mock("load_fixture.rb mock")
    to_path = mock("load_fixture_rb #to_path mock")
    name.should_receive(:to_path).and_return(to_path)
    to_path.should_receive(:to_str).and_return(@path)
    require_relative(name).should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  describe "(file extensions)" do
    it "loads a .rb extensioned file when passed a non-extensioned path" do
      require_relative("#{@dir}/load_fixture").should be_true
      ScratchPad.recorded.should == [:loaded]
    end

    it "loads a .rb extensioned file when a C-extension file of the same name is loaded" do
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.bundle"
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.dylib"
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.so"
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.dll"
      require_relative(@path).should be_true
      ScratchPad.recorded.should == [:loaded]
    end

    it "does not load a C-extension file if a .rb extensioned file is already loaded" do
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.rb"
      require_relative("#{@dir}/load_fixture").should be_false
      ScratchPad.recorded.should == []
    end

    it "loads a .rb extensioned file when passed a non-.rb extensioned path" do
      require_relative("#{@dir}/load_fixture.ext").should be_true
      ScratchPad.recorded.should == [:loaded]
      $LOADED_FEATURES.should include "#{@abs_dir}/load_fixture.ext.rb"
    end

    it "loads a .rb extensioned file when a complex-extensioned C-extension file of the same name is loaded" do
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.ext.bundle"
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.ext.dylib"
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.ext.so"
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.ext.dll"
      require_relative("#{@dir}/load_fixture.ext").should be_true
      ScratchPad.recorded.should == [:loaded]
      $LOADED_FEATURES.should include "#{@abs_dir}/load_fixture.ext.rb"
    end

    it "does not load a C-extension file if a complex-extensioned .rb file is already loaded" do
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.ext.rb"
      require_relative("#{@dir}/load_fixture.ext").should be_false
      ScratchPad.recorded.should == []
    end
  end

  describe "($LOADED_FEATURES)" do
    it "stores an absolute path" do
      require_relative(@path).should be_true
      $LOADED_FEATURES.should include(@abs_path)
    end

    platform_is_not :windows, :wasi do
      describe "with symlinks" do
        before :each do
          @symlink_to_code_dir = tmp("codesymlink")
          File.symlink(CODE_LOADING_DIR, @symlink_to_code_dir)
          @symlink_basename = File.basename(@symlink_to_code_dir)
          @requiring_file = tmp("requiring")
        end

        after :each do
          rm_r @symlink_to_code_dir, @requiring_file
        end

        it "does not canonicalize the path and stores a path with symlinks" do
          symlink_path = "#{@symlink_basename}/load_fixture.rb"
          absolute_path = "#{tmp("")}#{symlink_path}"
          canonical_path = "#{CODE_LOADING_DIR}/load_fixture.rb"
          touch(@requiring_file) { |f|
            f.puts "require_relative #{symlink_path.inspect}"
          }
          load(@requiring_file)
          ScratchPad.recorded.should == [:loaded]

          features = $LOADED_FEATURES.select { |path| path.end_with?('load_fixture.rb') }
          features.should include(absolute_path)
          features.should_not include(canonical_path)
        end

        it "stores the same path that __FILE__ returns in the required file" do
          symlink_path = "#{@symlink_basename}/load_fixture_and__FILE__.rb"
          touch(@requiring_file) { |f|
            f.puts "require_relative #{symlink_path.inspect}"
          }
          load(@requiring_file)
          loaded_feature = $LOADED_FEATURES.last
          ScratchPad.recorded.should == [loaded_feature]
        end
      end
    end

    it "does not store the path if the load fails" do
      saved_loaded_features = $LOADED_FEATURES.dup
      -> { require_relative("#{@dir}/raise_fixture.rb") }.should raise_error(RuntimeError)
      $LOADED_FEATURES.should == saved_loaded_features
    end

    it "does not load an absolute path that is already stored" do
      $LOADED_FEATURES << @abs_path
      require_relative(@path).should be_false
      ScratchPad.recorded.should == []
    end

    it "adds the suffix of the resolved filename" do
      require_relative("#{@dir}/load_fixture").should be_true
      $LOADED_FEATURES.should include("#{@abs_dir}/load_fixture.rb")
    end

    it "loads a path for a file already loaded with a relative path" do
      $LOAD_PATH << File.expand_path(@dir)
      $LOADED_FEATURES << "load_fixture.rb" << "load_fixture"
      require_relative(@path).should be_true
      $LOADED_FEATURES.should include(@abs_path)
      ScratchPad.recorded.should == [:loaded]
    end
  end
end

describe "Kernel#require_relative with an absolute path" do
  before :each do
    CodeLoadingSpecs.spec_setup
    @dir = File.expand_path "../../fixtures/code", __dir__
    @abs_dir = @dir
    @path = File.join @dir, "load_fixture.rb"
    @abs_path = @path
  end

  after :each do
    CodeLoadingSpecs.spec_cleanup
  end

  it "loads a path relative to the current file" do
    require_relative(@path).should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "loads a file defining many methods" do
    require_relative("#{@dir}/methods_fixture.rb").should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "raises a LoadError if the file does not exist" do
    -> { require_relative("#{@dir}/nonexistent.rb") }.should raise_error(LoadError)
    ScratchPad.recorded.should == []
  end

  it "raises a LoadError if basepath does not exist" do
    -> { eval("require_relative('#{@dir}/nonexistent.rb')") }.should raise_error(LoadError)
  end

  it "stores the missing path in a LoadError object" do
    path = "#{@dir}/nonexistent.rb"

    -> {
      require_relative(path)
    }.should(raise_error(LoadError) { |e|
      e.path.should == File.expand_path(path, @abs_dir)
    })
  end

  it "calls #to_str on non-String objects" do
    name = mock("load_fixture.rb mock")
    name.should_receive(:to_str).and_return(@path)
    require_relative(name).should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "raises a TypeError if argument does not respond to #to_str" do
    -> { require_relative(nil) }.should raise_error(TypeError)
    -> { require_relative(42) }.should raise_error(TypeError)
    -> {
      require_relative([@path,@path])
    }.should raise_error(TypeError)
  end

  it "raises a TypeError if passed an object that has #to_s but not #to_str" do
    name = mock("load_fixture.rb mock")
    name.stub!(:to_s).and_return(@path)
    -> { require_relative(name) }.should raise_error(TypeError)
  end

  it "raises a TypeError if #to_str does not return a String" do
    name = mock("#to_str returns nil")
    name.should_receive(:to_str).at_least(1).times.and_return(nil)
    -> { require_relative(name) }.should raise_error(TypeError)
  end

  it "calls #to_path on non-String objects" do
    name = mock("load_fixture.rb mock")
    name.should_receive(:to_path).and_return(@path)
    require_relative(name).should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "calls #to_str on non-String objects returned by #to_path" do
    name = mock("load_fixture.rb mock")
    to_path = mock("load_fixture_rb #to_path mock")
    name.should_receive(:to_path).and_return(to_path)
    to_path.should_receive(:to_str).and_return(@path)
    require_relative(name).should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  describe "(file extensions)" do
    it "loads a .rb extensioned file when passed a non-extensioned path" do
      require_relative("#{@dir}/load_fixture").should be_true
      ScratchPad.recorded.should == [:loaded]
    end

    it "loads a .rb extensioned file when a C-extension file of the same name is loaded" do
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.bundle"
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.dylib"
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.so"
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.dll"
      require_relative(@path).should be_true
      ScratchPad.recorded.should == [:loaded]
    end

    it "does not load a C-extension file if a .rb extensioned file is already loaded" do
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.rb"
      require_relative("#{@dir}/load_fixture").should be_false
      ScratchPad.recorded.should == []
    end

    it "loads a .rb extensioned file when passed a non-.rb extensioned path" do
      require_relative("#{@dir}/load_fixture.ext").should be_true
      ScratchPad.recorded.should == [:loaded]
      $LOADED_FEATURES.should include "#{@abs_dir}/load_fixture.ext.rb"
    end

    it "loads a .rb extensioned file when a complex-extensioned C-extension file of the same name is loaded" do
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.ext.bundle"
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.ext.dylib"
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.ext.so"
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.ext.dll"
      require_relative("#{@dir}/load_fixture.ext").should be_true
      ScratchPad.recorded.should == [:loaded]
      $LOADED_FEATURES.should include "#{@abs_dir}/load_fixture.ext.rb"
    end

    it "does not load a C-extension file if a complex-extensioned .rb file is already loaded" do
      $LOADED_FEATURES << "#{@abs_dir}/load_fixture.ext.rb"
      require_relative("#{@dir}/load_fixture.ext").should be_false
      ScratchPad.recorded.should == []
    end
  end

  describe "($LOAD_FEATURES)" do
    it "stores an absolute path" do
      require_relative(@path).should be_true
      $LOADED_FEATURES.should include(@abs_path)
    end

    it "does not store the path if the load fails" do
      saved_loaded_features = $LOADED_FEATURES.dup
      -> { require_relative("#{@dir}/raise_fixture.rb") }.should raise_error(RuntimeError)
      $LOADED_FEATURES.should == saved_loaded_features
    end

    it "does not load an absolute path that is already stored" do
      $LOADED_FEATURES << @abs_path
      require_relative(@path).should be_false
      ScratchPad.recorded.should == []
    end

    it "adds the suffix of the resolved filename" do
      require_relative("#{@dir}/load_fixture").should be_true
      $LOADED_FEATURES.should include("#{@abs_dir}/load_fixture.rb")
    end

    it "loads a path for a file already loaded with a relative path" do
      $LOAD_PATH << File.expand_path(@dir)
      $LOADED_FEATURES << "load_fixture.rb" << "load_fixture"
      require_relative(@path).should be_true
      $LOADED_FEATURES.should include(@abs_path)
      ScratchPad.recorded.should == [:loaded]
    end
  end
end
