require_relative 'spec_helper'

load_extension("struct")

describe "C-API Struct function" do
  before :each do
    @s = CApiStructSpecs.new
    @struct = @s.rb_struct_define("CAPIStruct", "a", "b", "c")
  end

  after :each do
    Struct.send(:remove_const, :CAPIStruct)
  end

  describe "rb_struct_define" do
    it "creates accessors for the struct members" do
      instance = @struct.new
      instance.a = 1
      instance.b = 2
      instance.c = 3
      instance.a.should == 1
      instance.b.should == 2
      instance.c.should == 3
    end

    it "has a value of nil for the member of a newly created instance" do
      # Verify that attributes are on an instance basis
      Struct::CAPIStruct.new.b.should be_nil
    end

    it "creates a constant scoped under Struct for the named Struct" do
      Struct.should have_constant(:CAPIStruct)
    end

    it "returns the member names as Symbols" do
      @struct.members.should == [:a, :b, :c]
    end
  end
end

describe "C-API Struct function" do
  before :each do
    @s = CApiStructSpecs.new
    @struct = @s.rb_struct_define(nil, "a", "b", "c")
  end

  describe "rb_struct_define for an anonymous struct" do
    it "creates accessors for the struct members" do
      instance = @struct.new
      instance.a = 1
      instance.b = 2
      instance.c = 3
      instance.a.should == 1
      instance.b.should == 2
      instance.c.should == 3
    end

    it "returns the member names as Symbols" do
      @struct.members.should == [:a, :b, :c]
    end
  end
end

describe "C-API Struct function" do
  before :all do
    @s = CApiStructSpecs.new
    @struct = @s.rb_struct_define_under(CApiStructSpecs, "CAPIStructUnder", "a", "b", "c")
  end

  describe "rb_struct_define_under" do
    it "creates accessors for the struct members" do
      instance = @struct.new
      instance.a = 1
      instance.b = 2
      instance.c = 3
      instance.a.should == 1
      instance.b.should == 2
      instance.c.should == 3
    end

    it "has a value of nil for the member of a newly created instance" do
      # Verify that attributes are on an instance basis
      CApiStructSpecs::CAPIStructUnder.new.b.should be_nil
    end

    it "does not create a constant scoped under Struct for the named Struct" do
      Struct.should_not have_constant(:CAPIStructUnder)
    end

    it "creates a constant scoped under the namespace of the given class" do
      CApiStructSpecs.should have_constant(:CAPIStructUnder)
    end

    it "returns the member names as Symbols" do
      @struct.members.should == [:a, :b, :c]
    end
  end
end

describe "C-API Struct function" do
  before :each do
    @s = CApiStructSpecs.new
    @klass = Struct.new(:a, :b, :c)
    @struct = @klass.new
  end

  describe "rb_struct_define" do
    it "raises an ArgumentError if arguments contain duplicate member name" do
      -> { @s.rb_struct_define(nil, "a", "b", "a") }.should raise_error(ArgumentError)
    end

    it "raises a NameError if an invalid constant name is given" do
      -> { @s.rb_struct_define("foo", "a", "b", "c") }.should raise_error(NameError)
    end
  end

  describe "rb_struct_aref" do
    it "returns the value of a struct member with a symbol key" do
      @struct[:a] = 2
      @s.rb_struct_aref(@struct, :a).should == 2
    end

    it "returns the value of a struct member with a string key" do
      @struct[:b] = 2
      @s.rb_struct_aref(@struct, "b").should == 2
    end

    it "returns the value of a struct member by index" do
      @struct[:c] = 3
      @s.rb_struct_aref(@struct, 2).should == 3
    end

    it "raises a NameError if the struct member does not exist" do
      -> { @s.rb_struct_aref(@struct, :d) }.should raise_error(NameError)
    end

    it "raises an IndexError if the given index is out of range" do
      -> { @s.rb_struct_aref(@struct, -4) }.should raise_error(IndexError)
      -> { @s.rb_struct_aref(@struct, 3) }.should raise_error(IndexError)
    end
  end

  describe "rb_struct_getmember" do
    it "returns the value of a struct member" do
      @struct[:a] = 2
      @s.rb_struct_getmember(@struct, :a).should == 2
    end

    it "raises a NameError if the struct member does not exist" do
      -> { @s.rb_struct_getmember(@struct, :d) }.should raise_error(NameError)
    end
  end

  describe "rb_struct_s_members" do
    it "returns the struct members as an array of symbols" do
      @s.rb_struct_s_members(@klass).should == [:a, :b, :c]
    end
  end

  describe "rb_struct_members" do
    it "returns the struct members as an array of symbols" do
      @s.rb_struct_members(@struct).should == [:a, :b, :c]
    end
  end

  describe "rb_struct_aset" do
    it "sets the value of a struct member with a symbol key" do
      @s.rb_struct_aset(@struct, :a, 1)
      @struct[:a].should == 1
    end

    it "sets the value of a struct member with a string key" do
      @s.rb_struct_aset(@struct, "b", 1)
      @struct[:b].should == 1
    end

    it "sets the value of a struct member by index" do
      @s.rb_struct_aset(@struct, 2, 1)
      @struct[:c].should == 1
    end

    it "raises a NameError if the struct member does not exist" do
      -> { @s.rb_struct_aset(@struct, :d, 1) }.should raise_error(NameError)
    end

    it "raises an IndexError if the given index is out of range" do
      -> { @s.rb_struct_aset(@struct, -4, 1) }.should raise_error(IndexError)
      -> { @s.rb_struct_aset(@struct, 3, 1) }.should raise_error(IndexError)
    end

    it "raises a FrozenError if the struct is frozen" do
      @struct.freeze
      -> { @s.rb_struct_aset(@struct, :a, 1) }.should raise_error(FrozenError)
    end
  end

  describe "rb_struct_new" do
    it "creates a new instance of a struct" do
      i = @s.rb_struct_new(@klass, 1, 2, 3)
      i.a.should == 1
      i.b.should == 2
      i.c.should == 3
    end
  end

  describe "rb_struct_size" do
    it "returns the number of struct members" do
      @s.rb_struct_size(@struct).should == 3
    end
  end

  describe "rb_struct_initialize" do
    it "sets all members" do
      @s.rb_struct_initialize(@struct, [1, 2, 3]).should == nil
      @struct.a.should == 1
      @struct.b.should == 2
      @struct.c.should == 3
    end

    it "does not freeze the Struct instance" do
      @s.rb_struct_initialize(@struct, [1, 2, 3]).should == nil
      @struct.should_not.frozen?
      @s.rb_struct_initialize(@struct, [4, 5, 6]).should == nil
      @struct.a.should == 4
      @struct.b.should == 5
      @struct.c.should == 6
    end

    it "raises ArgumentError if too many values" do
      -> { @s.rb_struct_initialize(@struct, [1, 2, 3, 4]) }.should raise_error(ArgumentError, "struct size differs")
    end

    it "treats missing values as nil" do
      @s.rb_struct_initialize(@struct, [1, 2]).should == nil
      @struct.a.should == 1
      @struct.b.should == 2
      @struct.c.should == nil
    end
  end
end

ruby_version_is "3.3" do
  describe "C-API Data function" do
    before :all do
      @s = CApiStructSpecs.new
      @klass = @s.rb_data_define(nil, "a", "b", "c")
    end

    describe "rb_data_define" do
      it "returns a subclass of Data class when passed nil as the first argument" do
        @klass.should.is_a? Class
        @klass.superclass.should == Data
      end

      it "returns a subclass of a class when passed as the first argument" do
        superclass = Class.new(Data)
        klass = @s.rb_data_define(superclass, "a", "b", "c")

        klass.should.is_a? Class
        klass.superclass.should == superclass
      end

      it "creates readers for the members" do
        obj = @klass.new(1, 2, 3)

        obj.a.should == 1
        obj.b.should == 2
        obj.c.should == 3
      end

      it "returns the member names as Symbols" do
        obj = @klass.new(0, 0, 0)

        obj.members.should == [:a, :b, :c]
      end

      it "raises an ArgumentError if arguments contain duplicate member name" do
        -> { @s.rb_data_define(nil, "a", "b", "a") }.should raise_error(ArgumentError)
      end

      it "raises when first argument is not a class" do
        -> { @s.rb_data_define([], "a", "b", "c") }.should raise_error(TypeError, "wrong argument type Array (expected Class)")
      end
    end

    describe "rb_struct_initialize" do
      it "sets all members for a Data instance" do
        data = @klass.allocate
        @s.rb_struct_initialize(data, [1, 2, 3]).should == nil
        data.a.should == 1
        data.b.should == 2
        data.c.should == 3
      end

      it "freezes the Data instance" do
        data = @klass.allocate
        @s.rb_struct_initialize(data, [1, 2, 3]).should == nil
        data.should.frozen?
        -> { @s.rb_struct_initialize(data, [1, 2, 3]) }.should raise_error(FrozenError)
      end

      it "raises ArgumentError if too many values" do
        data = @klass.allocate
        -> { @s.rb_struct_initialize(data, [1, 2, 3, 4]) }.should raise_error(ArgumentError, "struct size differs")
      end

      it "treats missing values as nil" do
        data = @klass.allocate
        @s.rb_struct_initialize(data, [1, 2]).should == nil
        data.a.should == 1
        data.b.should == 2
        data.c.should == nil
      end
    end
  end
end
