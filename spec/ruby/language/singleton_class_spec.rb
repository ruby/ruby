require_relative '../spec_helper'
require_relative '../fixtures/class'

describe "A singleton class" do
  it "is TrueClass for true" do
    true.singleton_class.should == TrueClass
  end

  it "is FalseClass for false" do
    false.singleton_class.should == FalseClass
  end

  it "is NilClass for nil" do
    nil.singleton_class.should == NilClass
  end

  it "raises a TypeError for Integer's" do
    -> { 1.singleton_class }.should.raise(TypeError)
  end

  it "raises a TypeError for symbols" do
    -> { :symbol.singleton_class }.should.raise(TypeError)
  end

  it "is a singleton Class instance" do
    o = mock('x')
    o.singleton_class.should.is_a?(Class)
    o.singleton_class.should_not.equal?(Object)
    o.should.is_a?(o.singleton_class)
  end

  it "is a Class for classes" do
    ClassSpecs::A.singleton_class.should.is_a?(Class)
  end

  it "inherits from Class for classes" do
    Object.singleton_class.ancestors.should.include?(Class)
  end

  it "is a subclass of Class's singleton class" do
    ec = ClassSpecs::A.singleton_class
    ec.should.is_a?(Class.singleton_class)
  end

  it "is a subclass of the same level of Class's singleton class" do
    ecec = ClassSpecs::A.singleton_class.singleton_class
    class_ec = Class.singleton_class

    ecec.should.is_a?(class_ec.singleton_class)
    ecec.should.is_a?(class_ec)
  end

  it "is a subclass of a superclass's singleton class" do
    ClassSpecs::K.singleton_class.superclass.should ==
      ClassSpecs::H.singleton_class
  end

  it "is a subclass of the same level of superclass's singleton class" do
    ClassSpecs::K.singleton_class.singleton_class.superclass.should ==
      ClassSpecs::H.singleton_class.singleton_class
  end

  it "for BasicObject has Class as its superclass" do
    BasicObject.singleton_class.superclass.should == Class
  end

  it "for BasicObject has the proper level of superclass for Class" do
    BasicObject.singleton_class.singleton_class.superclass.should ==
      Class.singleton_class
  end

  it "has class String as the superclass of a String instance" do
    "blah".dup.singleton_class.superclass.should == String
  end

  it "doesn't have singleton class" do
    -> { bignum_value.singleton_class }.should.raise(TypeError)
  end
end

describe "A constant on a singleton class" do
  before :each do
    @object = Object.new
    class << @object
      CONST = self
    end
  end

  it "can be accessed after the singleton class body is reopened" do
    class << @object
      CONST.should == self
    end
  end

  it "can be accessed via self::CONST" do
    class << @object
      self::CONST.should == self
    end
  end

  it "can be accessed via const_get" do
    class << @object
      const_get(:CONST).should == self
    end
  end

  it "is not defined on the object's class" do
    @object.class.const_defined?(:CONST).should == false
  end

  it "is not defined in the singleton class opener's scope" do
    class << @object
      CONST
    end
    -> { CONST }.should.raise(NameError)
  end

  it "cannot be accessed via object::CONST" do
    -> do
      @object::CONST
    end.should.raise(TypeError)
  end

  it "raises a NameError for anonymous_module::CONST" do
    @object = Class.new
    class << @object
      CONST = 100
    end

    -> do
      @object::CONST
    end.should.raise(NameError)
  end

  it "appears in the singleton class constant list" do
    @object.singleton_class.should.const_defined?(:CONST, false)
  end

  it "does not appear in the object's class constant list" do
    @object.class.should_not.const_defined?(:CONST)
  end

  it "is not preserved when the object is duped" do
    @object = @object.dup

    -> do
      class << @object; CONST; end
    end.should.raise(NameError)
  end

  it "is preserved when the object is cloned" do
    @object = @object.clone

    class << @object
      CONST.should_not == nil
    end
  end
end

describe "Defining instance methods on a singleton class" do
  before :each do
    @k = ClassSpecs::K.new
    class << @k
      def singleton_method; 1 end
    end

    @k_sc = @k.singleton_class
  end

  it "defines public methods" do
    @k_sc.public_instance_methods(false).should.include?(:singleton_method)
  end
end

describe "Instance methods of a singleton class" do
  before :each do
    k = ClassSpecs::K.new
    @k_sc = k.singleton_class
    @a_sc = ClassSpecs::A.new.singleton_class
    @a_c_sc = ClassSpecs::A.singleton_class
  end

  it "include ones of the object's class" do
    @k_sc.should.method_defined?(:example_instance_method, true)
  end

  it "does not include class methods of the object's class" do
    @k_sc.should_not.method_defined?(:example_class_method)
  end

  it "include instance methods of Object" do
    @a_sc.should.method_defined?(:example_instance_method_of_object, true)
  end

  it "does not include class methods of Object" do
    @a_sc.should_not.method_defined?(:example_class_method_of_object)
  end

  describe "for a class" do
    it "include instance methods of Class" do
      @a_c_sc.should.method_defined?(:example_instance_method_of_class, true)
    end

    it "does not include class methods of Class" do
      @a_c_sc.should_not.method_defined?(:example_class_method_of_class)
    end

    it "does not include instance methods of the singleton class of Class" do
      @a_c_sc.should_not.method_defined?(:example_instance_method_of_singleton_class)
    end

    it "does not include class methods of the singleton class of Class" do
      @a_c_sc.should_not.method_defined?(:example_class_method_of_singleton_class)
    end
  end

  describe "for a singleton class" do
    it "includes instance methods of the singleton class of Class" do
      @a_c_sc.singleton_class.should.method_defined?(:example_instance_method_of_singleton_class, true)
    end

    it "does not include class methods of the singleton class of Class" do
      @a_c_sc.singleton_class.should_not.method_defined?(:example_class_method_of_singleton_class)
    end
  end
end

describe "Class methods of a singleton class" do
  before :each do
    k = ClassSpecs::K.new
    @k_sc = k.singleton_class
    @a_sc = ClassSpecs::A.new.singleton_class
    @a_c_sc = ClassSpecs::A.singleton_class
  end

  it "include ones of the object's class" do
    @k_sc.should.respond_to?(:example_class_method)
  end

  it "does not include instance methods of the object's class" do
    @k_sc.should_not.respond_to?(:example_instance_method)
  end

  it "include instance methods of Class" do
    @a_sc.should.respond_to?(:example_instance_method_of_class)
  end

  it "does not include class methods of Class" do
    @a_sc.should_not.respond_to?(:example_class_method_of_class)
  end

  describe "for a class" do
    it "include instance methods of Class" do
      @a_c_sc.should.respond_to?(:example_instance_method_of_class)
    end

    it "include class methods of Class" do
      @a_c_sc.should.respond_to?(:example_class_method_of_class)
    end

    it "include instance methods of the singleton class of Class" do
      @a_c_sc.should.respond_to?(:example_instance_method_of_singleton_class)
    end

    it "does not include class methods of the singleton class of Class" do
      @a_c_sc.should_not.respond_to?(:example_class_method_of_singleton_class)
    end
  end

  describe "for a singleton class" do
    it "include instance methods of the singleton class of Class" do
      @a_c_sc.singleton_class.should.respond_to?(:example_instance_method_of_singleton_class)
    end

    it "include class methods of the singleton class of Class" do
      @a_c_sc.singleton_class.should.respond_to?(:example_class_method_of_singleton_class)
    end
  end
end

describe "Instantiating a singleton class" do
  it "raises a TypeError when new is called" do
    -> {
      Object.new.singleton_class.new
    }.should.raise(TypeError)
  end

  it "raises a TypeError when allocate is called" do
    -> {
      Object.new.singleton_class.allocate
    }.should.raise(TypeError)
  end
end

describe "Frozen properties" do
  it "is frozen if the object it is created from is frozen" do
    o = Object.new
    o.freeze
    klass = o.singleton_class
    klass.frozen?.should == true
  end

  it "will be frozen if the object it is created from becomes frozen" do
    o = Object.new
    klass = o.singleton_class
    klass.frozen?.should == false
    o.freeze
    klass.frozen?.should == true
  end

  it "will be unfrozen if the frozen object is cloned with freeze set to false" do
    o = Object.new
    o.freeze
    o2 = o.clone(freeze: false)
    o2.singleton_class.frozen?.should == false
  end
end
