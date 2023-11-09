require_relative '../../spec_helper'
require_relative '../../fixtures/constants'

describe "Module#const_source_location" do
  before do
    @constants_fixture_path = File.expand_path('../../fixtures/constants.rb', __dir__)
  end

  describe "with dynamically assigned constants" do
    it "searches a path in the immediate class or module first" do
      ConstantSpecs::ClassA::CSL_CONST301 = :const301_1
      ConstantSpecs::ClassA.const_source_location(:CSL_CONST301).should == [__FILE__, __LINE__ - 1]

      ConstantSpecs::ModuleA::CSL_CONST301 = :const301_2
      ConstantSpecs::ModuleA.const_source_location(:CSL_CONST301).should == [__FILE__, __LINE__ - 1]

      ConstantSpecs::ParentA::CSL_CONST301 = :const301_3
      ConstantSpecs::ParentA.const_source_location(:CSL_CONST301).should == [__FILE__, __LINE__ - 1]

      ConstantSpecs::ContainerA::ChildA::CSL_CONST301 = :const301_5
      ConstantSpecs::ContainerA::ChildA.const_source_location(:CSL_CONST301).should == [__FILE__, __LINE__ - 1]
    end

    it "searches a path in a module included in the immediate class before the superclass" do
      ConstantSpecs::ParentB::CSL_CONST302 = :const302_1
      ConstantSpecs::ModuleF::CSL_CONST302 = :const302_2
      ConstantSpecs::ContainerB::ChildB.const_source_location(:CSL_CONST302).should == [__FILE__, __LINE__ - 1]
    end

    it "searches a path in the superclass before a module included in the superclass" do
      ConstantSpecs::ModuleE::CSL_CONST303 = :const303_1
      ConstantSpecs::ParentB::CSL_CONST303 = :const303_2
      ConstantSpecs::ContainerB::ChildB.const_source_location(:CSL_CONST303).should == [__FILE__, __LINE__ - 1]
    end

    it "searches a path in a module included in the superclass" do
      ConstantSpecs::ModuleA::CSL_CONST304 = :const304_1
      ConstantSpecs::ModuleE::CSL_CONST304 = :const304_2
      ConstantSpecs::ContainerB::ChildB.const_source_location(:CSL_CONST304).should == [__FILE__, __LINE__ - 1]
    end

    it "searches a path in the superclass chain" do
      ConstantSpecs::ModuleA::CSL_CONST305 = :const305
      ConstantSpecs::ContainerB::ChildB.const_source_location(:CSL_CONST305).should == [__FILE__, __LINE__ - 1]
    end

    it "returns path to a toplevel constant when the receiver is a Class" do
      Object::CSL_CONST306 = :const306
      ConstantSpecs::ContainerB::ChildB.const_source_location(:CSL_CONST306).should == [__FILE__, __LINE__ - 1]
    end

    it "returns path to a toplevel constant when the receiver is a Module" do
      Object::CSL_CONST308 = :const308
      ConstantSpecs.const_source_location(:CSL_CONST308).should == [__FILE__, __LINE__ - 1]
      ConstantSpecs::ModuleA.const_source_location(:CSL_CONST308).should == [__FILE__, __LINE__ - 2]
    end

    it "returns path to the updated value of a constant" do
      ConstantSpecs::ClassB::CSL_CONST309 = :const309_1
      ConstantSpecs::ClassB.const_source_location(:CSL_CONST309).should == [__FILE__, __LINE__ - 1]

      -> {
        ConstantSpecs::ClassB::CSL_CONST309 = :const309_2
      }.should complain(/already initialized constant/)
      ConstantSpecs::ClassB.const_source_location(:CSL_CONST309).should == [__FILE__, __LINE__ - 2]
    end
  end

  describe "with statically assigned constants" do
    it "works for the module and class keywords" do
      ConstantSpecs.const_source_location(:ModuleB).should == [@constants_fixture_path, ConstantSpecs::ModuleB::LINE]
      ConstantSpecs.const_source_location(:ClassA).should == [@constants_fixture_path, ConstantSpecs::ClassA::LINE]
    end

    it "searches location path the immediate class or module first" do
      ConstantSpecs::ClassA.const_source_location(:CS_CONST10).should == [@constants_fixture_path, ConstantSpecs::ClassA::CS_CONST10_LINE]
      ConstantSpecs::ModuleA.const_source_location(:CS_CONST10).should == [@constants_fixture_path, ConstantSpecs::ModuleA::CS_CONST10_LINE]
      ConstantSpecs::ParentA.const_source_location(:CS_CONST10).should == [@constants_fixture_path, ConstantSpecs::ParentA::CS_CONST10_LINE]
      ConstantSpecs::ContainerA.const_source_location(:CS_CONST10).should == [@constants_fixture_path, ConstantSpecs::ContainerA::CS_CONST10_LINE]
      ConstantSpecs::ContainerA::ChildA.const_source_location(:CS_CONST10).should == [@constants_fixture_path, ConstantSpecs::ContainerA::ChildA::CS_CONST10_LINE]
    end

    it "searches location path a module included in the immediate class before the superclass" do
      ConstantSpecs::ContainerA::ChildA.const_source_location(:CS_CONST15).should == [@constants_fixture_path, ConstantSpecs::ModuleC::CS_CONST15_LINE]
    end

    it "searches location path the superclass before a module included in the superclass" do
      ConstantSpecs::ContainerA::ChildA.const_source_location(:CS_CONST11).should == [@constants_fixture_path, ConstantSpecs::ParentA::CS_CONST11_LINE]
    end

    it "searches location path a module included in the superclass" do
      ConstantSpecs::ContainerA::ChildA.const_source_location(:CS_CONST12).should == [@constants_fixture_path, ConstantSpecs::ModuleB::CS_CONST12_LINE]
    end

    it "searches location path the superclass chain" do
      ConstantSpecs::ContainerA::ChildA.const_source_location(:CS_CONST13).should == [@constants_fixture_path, ConstantSpecs::ModuleA::CS_CONST13_LINE]
    end

    it "returns location path a toplevel constant when the receiver is a Class" do
      ConstantSpecs::ContainerA::ChildA.const_source_location(:CS_CONST1).should == [@constants_fixture_path, CS_CONST1_LINE]
    end

    it "returns location path a toplevel constant when the receiver is a Module" do
      ConstantSpecs.const_source_location(:CS_CONST1).should == [@constants_fixture_path, CS_CONST1_LINE]
      ConstantSpecs::ModuleA.const_source_location(:CS_CONST1).should == [@constants_fixture_path, CS_CONST1_LINE]
    end
  end

  it "return empty path if constant defined in C code" do
    Object.const_source_location(:String).should == []
  end

  it "accepts a String or Symbol name" do
    Object.const_source_location(:CS_CONST1).should == [@constants_fixture_path, CS_CONST1_LINE]
    Object.const_source_location("CS_CONST1").should == [@constants_fixture_path, CS_CONST1_LINE]
  end

  it "returns nil if no constant is defined in the search path" do
    ConstantSpecs.const_source_location(:CS_CONSTX).should == nil
  end

  it "raises a NameError if the name does not start with a capital letter" do
    -> { ConstantSpecs.const_source_location "name" }.should raise_error(NameError)
  end

  it "raises a NameError if the name starts with a non-alphabetic character" do
    -> { ConstantSpecs.const_source_location "__CONSTX__" }.should raise_error(NameError)
    -> { ConstantSpecs.const_source_location "@CS_CONST1" }.should raise_error(NameError)
    -> { ConstantSpecs.const_source_location "!CS_CONST1" }.should raise_error(NameError)
  end

  it "raises a NameError if the name contains non-alphabetic characters except '_'" do
    Object.const_source_location("CS_CONST1").should == [@constants_fixture_path, CS_CONST1_LINE]
    -> { ConstantSpecs.const_source_location "CS_CONST1=" }.should raise_error(NameError)
    -> { ConstantSpecs.const_source_location "CS_CONST1?" }.should raise_error(NameError)
  end

  it "calls #to_str to convert the given name to a String" do
    name = mock("ClassA")
    name.should_receive(:to_str).and_return("ClassA")
    ConstantSpecs.const_source_location(name).should == [@constants_fixture_path, ConstantSpecs::ClassA::LINE]
  end

  it "raises a TypeError if conversion to a String by calling #to_str fails" do
    name = mock('123')
    -> { ConstantSpecs.const_source_location(name) }.should raise_error(TypeError)

    name.should_receive(:to_str).and_return(123)
    -> { ConstantSpecs.const_source_location(name) }.should raise_error(TypeError)
  end

  it "does not search the singleton class of a Class or Module" do
    ConstantSpecs::ContainerA::ChildA.const_source_location(:CS_CONST14).should == nil
    ConstantSpecs.const_source_location(:CS_CONST14).should == nil
  end

  it "does not search the containing scope" do
    ConstantSpecs::ContainerA::ChildA.const_source_location(:CS_CONST20).should == [@constants_fixture_path, ConstantSpecs::ParentA::CS_CONST20_LINE]
    ConstantSpecs::ContainerA::ChildA.const_source_location(:CS_CONST5) == nil
  end

  it "returns nil if the constant is defined in the receiver's superclass and the inherit flag is false" do
    ConstantSpecs::ContainerA::ChildA.const_source_location(:CS_CONST4, false).should == nil
  end

  it "searches into the receiver superclasses if the inherit flag is true" do
    ConstantSpecs::ContainerA::ChildA.const_source_location(:CS_CONST4, true).should == [@constants_fixture_path, ConstantSpecs::ParentA::CS_CONST4_LINE]
  end

  it "returns nil when the receiver is a Module, the constant is defined at toplevel and the inherit flag is false" do
    ConstantSpecs::ModuleA.const_source_location(:CS_CONST1, false).should == nil
  end

  it "returns nil when the receiver is a Class, the constant is defined at toplevel and the inherit flag is false" do
    ConstantSpecs::ContainerA::ChildA.const_source_location(:CS_CONST1, false).should == nil
  end

  it "accepts a toplevel scope qualifier" do
    ConstantSpecs.const_source_location("::CS_CONST1").should == [@constants_fixture_path, CS_CONST1_LINE]
  end

  it "accepts a scoped constant name" do
    ConstantSpecs.const_source_location("ClassA::CS_CONST10").should == [@constants_fixture_path, ConstantSpecs::ClassA::CS_CONST10_LINE]
  end

  it "returns updated location from const_set" do
    mod = Module.new
    const_line = __LINE__ + 1
    mod.const_set :Foo, 1
    mod.const_source_location(:Foo).should == [__FILE__, const_line]
  end

  it "raises a NameError if the name includes two successive scope separators" do
    -> { ConstantSpecs.const_source_location("ClassA::::CS_CONST10") }.should raise_error(NameError)
  end

  it "raises a NameError if only '::' is passed" do
    -> { ConstantSpecs.const_source_location("::") }.should raise_error(NameError)
  end

  it "raises a NameError if a Symbol has a toplevel scope qualifier" do
    -> { ConstantSpecs.const_source_location(:'::CS_CONST1') }.should raise_error(NameError)
  end

  it "raises a NameError if a Symbol is a scoped constant name" do
    -> { ConstantSpecs.const_source_location(:'ClassA::CS_CONST10') }.should raise_error(NameError)
  end

  it "does search private constants path" do
     ConstantSpecs.const_source_location(:CS_PRIVATE).should == [@constants_fixture_path, ConstantSpecs::CS_PRIVATE_LINE]
  end

  it "works for eval with a given line" do
    c = Class.new do
      eval('self::C = 1', nil, "foo", 100)
    end
    c.const_source_location(:C).should == ["foo", 100]
  end

  context 'autoload' do
    before :all do
      ConstantSpecs.autoload :CSL_CONST1, "#{__dir__}/notexisting.rb"
      @line = __LINE__ - 1
    end

    it 'returns the autoload location while not resolved' do
      ConstantSpecs.const_source_location('CSL_CONST1').should == [__FILE__, @line]
    end

    it 'returns where the constant was resolved when resolved' do
      file = fixture(__FILE__, 'autoload_location.rb')
      ConstantSpecs.autoload :CONST_LOCATION, file
      line = ConstantSpecs::CONST_LOCATION
      ConstantSpecs.const_source_location('CONST_LOCATION').should == [file, line]
    end
  end
end
