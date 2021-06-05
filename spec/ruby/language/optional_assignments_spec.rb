require_relative '../spec_helper'
require_relative '../fixtures/constants'

describe 'Optional variable assignments' do
  describe 'using ||=' do
    describe 'using a single variable' do
      it 'assigns a new variable' do
        a ||= 10

        a.should == 10
      end

      it 're-assigns an existing variable set to false' do
        a = false
        a ||= 10

        a.should == 10
      end

      it 're-assigns an existing variable set to nil' do
        a = nil
        a ||= 10

        a.should == 10
      end

      it 'does not re-assign a variable with a truthy value' do
        a = 10
        a ||= 20

        a.should == 10
      end

      it 'does not evaluate the right side when not needed' do
        a = 10
        a ||= raise('should not be executed')
        a.should == 10
      end

      it 'does not re-assign a variable with a truthy value when using an inline rescue' do
        a = 10
        a ||= 20 rescue 30

        a.should == 10
      end

      it 'returns the new value if set to false' do
        a = false

        (a ||= 20).should == 20
      end

      it 'returns the original value if truthy' do
        a = 10

        (a ||= 20).should == 10
      end
    end

    describe 'using a accessor' do
      before do
        klass = Class.new { attr_accessor :b }
        @a    = klass.new
      end

      it 'assigns a new variable' do
        @a.b ||= 10

        @a.b.should == 10
      end

      it 're-assigns an existing variable set to false' do
        @a.b = false
        @a.b ||= 10

        @a.b.should == 10
      end

      it 're-assigns an existing variable set to nil' do
        @a.b = nil
        @a.b ||= 10

        @a.b.should == 10
      end

      it 'does not re-assign a variable with a truthy value' do
        @a.b = 10
        @a.b ||= 20

        @a.b.should == 10
      end

      it 'does not evaluate the right side when not needed' do
        @a.b = 10
        @a.b ||= raise('should not be executed')
        @a.b.should == 10
      end

      it 'does not re-assign a variable with a truthy value when using an inline rescue' do
        @a.b = 10
        @a.b ||= 20 rescue 30

        @a.b.should == 10
      end

      it 'returns the new value if set to false' do
        def @a.b=(x)
          :v
        end

        @a.b = false
        (@a.b ||= 20).should == 20
      end

      it 'returns the original value if truthy' do
        def @a.b=(x)
          @b = x
          :v
        end

        @a.b = 10
        (@a.b ||= 20).should == 10
      end

      it 'works when writer is private' do
        klass = Class.new do
          def t
            self.b = false
            (self.b ||= 10).should == 10
            (self.b ||= 20).should == 10
          end

          def b
            @b
          end

          def b=(x)
            @b = x
            :v
          end

          private :b=
        end

        klass.new.t
      end

    end
  end

  describe 'using &&=' do
    describe 'using a single variable' do
      it 'leaves new variable unassigned' do
        a &&= 10

        a.should == nil
      end

      it 'leaves false' do
        a = false
        a &&= 10

        a.should == false
      end

      it 'leaves nil' do
        a = nil
        a &&= 10

        a.should == nil
      end

      it 'does not evaluate the right side when not needed' do
        a = nil
        a &&= raise('should not be executed')
        a.should == nil
      end

      it 'does re-assign a variable with a truthy value' do
        a = 10
        a &&= 20

        a.should == 20
      end

      it 'does re-assign a variable with a truthy value when using an inline rescue' do
        a = 10
        a &&= 20 rescue 30

        a.should == 20
      end
    end

    describe 'using a single variable' do
      before do
        klass = Class.new { attr_accessor :b }
        @a    = klass.new
      end

      it 'leaves new variable unassigned' do
        @a.b &&= 10

        @a.b.should == nil
      end

      it 'leaves false' do
        @a.b = false
        @a.b &&= 10

        @a.b.should == false
      end

      it 'leaves nil' do
        @a.b = nil
        @a.b &&= 10

        @a.b.should == nil
      end

      it 'does not evaluate the right side when not needed' do
        @a.b = nil
        @a.b &&= raise('should not be executed')
        @a.b.should == nil
      end

      it 'does re-assign a variable with a truthy value' do
        @a.b = 10
        @a.b &&= 20

        @a.b.should == 20
      end

      it 'does re-assign a variable with a truthy value when using an inline rescue' do
        @a.b = 10
        @a.b &&= 20 rescue 30

        @a.b.should == 20
      end
    end

    describe 'using a #[]' do
      before do
        @a = {}
        klass = Class.new do
          def [](k)
            @hash ||= {}
            @hash[k]
          end

          def []=(k, v)
            @hash ||= {}
            @hash[k] = v
            7
          end
        end
        @b = klass.new
      end

      it 'leaves new variable unassigned' do
        @a[:k] &&= 10

        @a.key?(:k).should == false
      end

      it 'leaves false' do
        @a[:k] = false
        @a[:k] &&= 10

        @a[:k].should == false
      end

      it 'leaves nil' do
        @a[:k] = nil
        @a[:k] &&= 10

        @a[:k].should == nil
      end

      it 'does not evaluate the right side when not needed' do
        @a[:k] = nil
        @a[:k] &&= raise('should not be executed')
        @a[:k].should == nil
      end

      it 'does re-assign a variable with a truthy value' do
        @a[:k] = 10
        @a[:k] &&= 20

        @a[:k].should == 20
      end

      it 'does re-assign a variable with a truthy value when using an inline rescue' do
        @a[:k] = 10
        @a[:k] &&= 20 rescue 30

        @a[:k].should == 20
      end

      it 'returns the assigned value, not the result of the []= method with ||=' do
        (@b[:k] ||= 12).should == 12
      end

      it 'returns the assigned value, not the result of the []= method with +=' do
        @b[:k] = 17
        (@b[:k] += 12).should == 29
      end
    end
  end

  describe 'using compounded constants' do
    before :each do
      Object.send(:remove_const, :A) if defined? Object::A
    end

    after :each do
      Object.send(:remove_const, :A) if defined? Object::A
    end

    it 'with ||= assignments' do
      Object::A ||= 10
      Object::A.should == 10
    end

    it 'with ||= do not reassign' do
      Object::A = 20
      Object::A ||= 10
      Object::A.should == 20
    end

    it 'with &&= assignments' do
      Object::A = 20
      -> {
        Object::A &&= 10
      }.should complain(/already initialized constant/)
      Object::A.should == 10
    end

    it 'with &&= assignments will fail with non-existent constants' do
      -> { Object::A &&= 10 }.should raise_error(NameError)
    end

    it 'with operator assignments' do
      Object::A = 20
      -> {
        Object::A += 10
      }.should complain(/already initialized constant/)
      Object::A.should == 30
    end

    it 'with operator assignments will fail with non-existent constants' do
      -> { Object::A += 10 }.should raise_error(NameError)
    end
  end
end

describe 'Optional constant assignment' do
  describe 'with ||=' do
    it "assigns a scoped constant if previously undefined" do
      ConstantSpecs.should_not have_constant(:OpAssignUndefined)
      module ConstantSpecs
        OpAssignUndefined ||= 42
      end
      ConstantSpecs::OpAssignUndefined.should == 42
      ConstantSpecs::OpAssignUndefinedOutside ||= 42
      ConstantSpecs::OpAssignUndefinedOutside.should == 42
      ConstantSpecs.send(:remove_const, :OpAssignUndefined)
      ConstantSpecs.send(:remove_const, :OpAssignUndefinedOutside)
    end

    it "assigns a global constant if previously undefined" do
      OpAssignGlobalUndefined ||= 42
      ::OpAssignGlobalUndefinedExplicitScope ||= 42
      OpAssignGlobalUndefined.should == 42
      ::OpAssignGlobalUndefinedExplicitScope.should == 42
      Object.send :remove_const, :OpAssignGlobalUndefined
      Object.send :remove_const, :OpAssignGlobalUndefinedExplicitScope
    end

    it 'correctly defines non-existing constants' do
      ConstantSpecs::ClassA::OR_ASSIGNED_CONSTANT1 ||= :assigned
      ConstantSpecs::ClassA::OR_ASSIGNED_CONSTANT1.should == :assigned
    end

    it 'correctly overwrites nil constants' do
      suppress_warning do # already initialized constant
      ConstantSpecs::ClassA::NIL_OR_ASSIGNED_CONSTANT1 = nil
      ConstantSpecs::ClassA::NIL_OR_ASSIGNED_CONSTANT1 ||= :assigned
      ConstantSpecs::ClassA::NIL_OR_ASSIGNED_CONSTANT1.should == :assigned
      end
    end

    it 'causes side-effects of the module part to be applied only once (for undefined constant)' do
      x = 0
      (x += 1; ConstantSpecs::ClassA)::OR_ASSIGNED_CONSTANT2 ||= :assigned
      x.should == 1
      ConstantSpecs::ClassA::OR_ASSIGNED_CONSTANT2.should == :assigned
    end

    it 'causes side-effects of the module part to be applied (for nil constant)' do
      suppress_warning do # already initialized constant
      ConstantSpecs::ClassA::NIL_OR_ASSIGNED_CONSTANT2 = nil
      x = 0
      (x += 1; ConstantSpecs::ClassA)::NIL_OR_ASSIGNED_CONSTANT2 ||= :assigned
      x.should == 1
      ConstantSpecs::ClassA::NIL_OR_ASSIGNED_CONSTANT2.should == :assigned
      end
    end

    it 'does not evaluate the right-hand side if the module part raises an exception (for undefined constant)' do
      x = 0
      y = 0

      -> {
        (x += 1; raise Exception; ConstantSpecs::ClassA)::OR_ASSIGNED_CONSTANT3 ||= (y += 1; :assigned)
      }.should raise_error(Exception)

      x.should == 1
      y.should == 0
      defined?(ConstantSpecs::ClassA::OR_ASSIGNED_CONSTANT3).should == nil
    end

    it 'does not evaluate the right-hand side if the module part raises an exception (for nil constant)' do
      ConstantSpecs::ClassA::NIL_OR_ASSIGNED_CONSTANT3 = nil
      x = 0
      y = 0

      -> {
        (x += 1; raise Exception; ConstantSpecs::ClassA)::NIL_OR_ASSIGNED_CONSTANT3 ||= (y += 1; :assigned)
      }.should raise_error(Exception)

      x.should == 1
      y.should == 0
      ConstantSpecs::ClassA::NIL_OR_ASSIGNED_CONSTANT3.should == nil
    end
  end

  describe "with &&=" do
    it "re-assigns a scoped constant if already true" do
      module ConstantSpecs
        OpAssignTrue = true
      end
      suppress_warning do
        ConstantSpecs::OpAssignTrue &&= 1
      end
      ConstantSpecs::OpAssignTrue.should == 1
      ConstantSpecs.send :remove_const, :OpAssignTrue
    end

    it "leaves scoped constant if not true" do
      module ConstantSpecs
        OpAssignFalse = false
      end
      ConstantSpecs::OpAssignFalse &&= 1
      ConstantSpecs::OpAssignFalse.should == false
      ConstantSpecs.send :remove_const, :OpAssignFalse
    end
  end
end
