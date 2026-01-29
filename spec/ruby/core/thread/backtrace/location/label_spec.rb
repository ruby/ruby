require_relative '../../../../spec_helper'
require_relative 'fixtures/classes'

describe 'Thread::Backtrace::Location#label' do
  it 'returns the base label of the call frame' do
    ThreadBacktraceLocationSpecs.locations[0].label.should include('<top (required)>')
  end

  it 'returns the method name for a method location' do
    ThreadBacktraceLocationSpecs.method_location[0].label.should =~ /\A(?:ThreadBacktraceLocationSpecs\.)?method_location\z/
  end

  it 'returns the block name for a block location' do
    ThreadBacktraceLocationSpecs.block_location[0].label.should =~ /\Ablock in (?:ThreadBacktraceLocationSpecs\.)?block_location\z/
  end

  it 'returns the module name for a module location' do
    ThreadBacktraceLocationSpecs::MODULE_LOCATION[0].label.should == "<module:ThreadBacktraceLocationSpecs>"
  end

  it 'includes the nesting level of a block as part of the location label' do
    first_level_location, second_level_location, third_level_location =
      ThreadBacktraceLocationSpecs.locations_inside_nested_blocks

    first_level_location.label.should =~ /\Ablock in (?:ThreadBacktraceLocationSpecs\.)?locations_inside_nested_blocks\z/
    second_level_location.label.should =~ /\Ablock \(2 levels\) in (?:ThreadBacktraceLocationSpecs\.)?locations_inside_nested_blocks\z/
    third_level_location.label.should =~ /\Ablock \(3 levels\) in (?:ThreadBacktraceLocationSpecs\.)?locations_inside_nested_blocks\z/
  end

  it 'sets the location label for a top-level block differently depending on it being in the main file or a required file' do
    path = fixture(__FILE__, "locations_in_main.rb")
    main_label, required_label = ruby_exe(path).lines

    main_label.should == "block in <main>\n"
    required_label.should == "block in <top (required)>\n"
  end

  it "return the same name as the caller for eval" do
    this = caller_locations(0)[0].label
    eval("caller_locations(0)[0]").label.should == this

    b = binding
    b.eval("caller_locations(0)[0]").label.should == this

    b.local_variable_set(:binding_var1, 1)
    b.eval("caller_locations(0)[0]").label.should == this

    b.local_variable_set(:binding_var2, 2)
    b.eval("caller_locations(0)[0]").label.should == this

    b.local_variable_set(:binding_var2, 2)
    eval("caller_locations(0)[0]", b).label.should == this
  end

  ruby_version_is "3.4" do
    describe "is Module#method for" do
      it "a core method defined natively" do
        BasicObject.instance_method(:instance_exec).should_not.source_location
        loc = nil
        loc = instance_exec { caller_locations(1, 1)[0] }
        loc.label.should == "BasicObject#instance_exec"
      end

      it "a core method defined in Ruby" do
        Kernel.instance_method(:tap).should.source_location
        loc = nil
        tap { loc = caller_locations(1, 1)[0] }
        loc.label.should == "Kernel#tap"
      end

      it "an instance method defined in Ruby" do
        ThreadBacktraceLocationSpecs::INSTANCE.instance_method_location[0].label.should == "ThreadBacktraceLocationSpecs#instance_method_location"
      end

      it "a block in an instance method defined in Ruby" do
        ThreadBacktraceLocationSpecs::INSTANCE.instance_block_location[0].label.should == "block in ThreadBacktraceLocationSpecs#instance_block_location"
      end

      it "a nested block in an instance method defined in Ruby" do
        ThreadBacktraceLocationSpecs::INSTANCE.instance_locations_inside_nested_block[0].label.should == "block (2 levels) in ThreadBacktraceLocationSpecs#instance_locations_inside_nested_block"
      end

      it "a method defined via module_exec" do
        ThreadBacktraceLocationSpecs.module_exec do
          def in_module_exec
            caller_locations(0)
          end
        end
        ThreadBacktraceLocationSpecs::INSTANCE.in_module_exec[0].label.should == "ThreadBacktraceLocationSpecs#in_module_exec"
      end

      it "a method defined via module_eval" do
        ThreadBacktraceLocationSpecs.module_eval <<~RUBY
          def in_module_eval
            caller_locations(0)
          end
        RUBY
        ThreadBacktraceLocationSpecs::INSTANCE.in_module_eval[0].label.should == "ThreadBacktraceLocationSpecs#in_module_eval"
      end
    end

    describe "is Module.method for" do
      it "a singleton method defined in Ruby" do
        ThreadBacktraceLocationSpecs.method_location[0].label.should == "ThreadBacktraceLocationSpecs.method_location"
      end

      it "a block in a singleton method defined in Ruby" do
        ThreadBacktraceLocationSpecs.block_location[0].label.should == "block in ThreadBacktraceLocationSpecs.block_location"
      end

      it "a nested block in a singleton method defined in Ruby" do
        ThreadBacktraceLocationSpecs.locations_inside_nested_blocks[2].label.should == "block (3 levels) in ThreadBacktraceLocationSpecs.locations_inside_nested_blocks"
      end

      it "a singleton method defined via def Const.method" do
        def ThreadBacktraceLocationSpecs.def_singleton
          caller_locations(0)
        end
        ThreadBacktraceLocationSpecs.def_singleton[0].label.should == "ThreadBacktraceLocationSpecs.def_singleton"
      end
    end

    it "shows the original method name for an aliased method" do
      ThreadBacktraceLocationSpecs::INSTANCE.aliased_method.should == "ThreadBacktraceLocationSpecs#original_method"
    end

    # A wide variety of cases.
    # These show interesting cases when trying to determine the name statically/at parse time
    describe "is correct for" do
      base = ThreadBacktraceLocationSpecs

      it "M::C#regular_instance_method" do
        base::M::C.new.regular_instance_method.should == "#{base}::M::C#regular_instance_method"
      end

      it "M::C.sdef_class_method" do
        base::M::C.sdef_class_method.should == "#{base}::M::C.sdef_class_method"
      end

      it "M::C.sclass_method" do
        base::M::C.sclass_method.should == "#{base}::M::C.sclass_method"
      end

      it "M::C.block_in_sclass_method" do
        base::M::C.block_in_sclass_method.should == "block (2 levels) in #{base}::M::C.block_in_sclass_method"
      end

      it "M::D#scoped_method" do
        base::M::D.new.scoped_method.should == "#{base}::M::D#scoped_method"
      end

      it "M::D.sdef_scoped_method" do
        base::M::D.sdef_scoped_method.should == "#{base}::M::D.sdef_scoped_method"
      end

      it "M::D.sclass_scoped_method" do
        base::M::D.sclass_scoped_method.should == "#{base}::M::D.sclass_scoped_method"
      end

      it "ThreadBacktraceLocationSpecs#top" do
        ThreadBacktraceLocationSpecs::INSTANCE.top.should == "ThreadBacktraceLocationSpecs#top"
      end

      it "ThreadBacktraceLocationSpecs::Nested#top_nested" do
        ThreadBacktraceLocationSpecs::Nested.new.top_nested.should == "ThreadBacktraceLocationSpecs::Nested#top_nested"
      end

      it "ThreadBacktraceLocationSpecs::Nested::C#top_nested_c" do
        ThreadBacktraceLocationSpecs::Nested::C.new.top_nested_c.should == "ThreadBacktraceLocationSpecs::Nested::C#top_nested_c"
      end

      it "Object#label_top_method" do
        label_top_method.should == "Object#label_top_method"
      end

      it "main.label_sdef_method_of_main" do
        main = TOPLEVEL_BINDING.receiver
        main.label_sdef_method_of_main.should == "label_sdef_method_of_main"
      end

      it "main.label_sclass_method_of_main" do
        main = TOPLEVEL_BINDING.receiver
        main.label_sclass_method_of_main.should == "label_sclass_method_of_main"
      end

      it "unknown_def_singleton_method" do
        base::SOME_OBJECT.unknown_def_singleton_method.should == "unknown_def_singleton_method"
      end

      it "unknown_sdef_singleton_method" do
        base::SOME_OBJECT.unknown_sdef_singleton_method.should == "unknown_sdef_singleton_method"
      end

      it "M#module_eval_method" do
        Object.new.extend(base::M).module_eval_method.should == "#{base}::M#module_eval_method"
      end

      it "M.sdef_module_eval_method" do
        base::M.sdef_module_eval_method.should == "#{base}::M.sdef_module_eval_method"
      end

      it "ThreadBacktraceLocationSpecs.string_class_method" do
        ThreadBacktraceLocationSpecs.string_class_method.should == "ThreadBacktraceLocationSpecs.string_class_method"
      end

      it "ThreadBacktraceLocationSpecs.nested_class_method" do
        ThreadBacktraceLocationSpecs.nested_class_method.should == "ThreadBacktraceLocationSpecs.nested_class_method"
      end

      it "M#mod_function" do
        Object.new.extend(base::M).send(:mod_function).should == "#{base}::M#mod_function"
      end

      it "M.mod_function" do
        base::M.mod_function.should == "#{base}::M.mod_function"
      end

      it "sdef_expression" do
        base.sdef_expression.should == "#{base}.sdef_expression"
      end

      it "block_in_sdef_expression" do
        base.block_in_sdef_expression.should == "block in #{base}.block_in_sdef_expression"
      end
    end
  end
end
