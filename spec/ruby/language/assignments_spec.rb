require_relative '../spec_helper'

# Should be synchronized with spec/ruby/language/optional_assignments_spec.rb
# Some specs for assignments are located in language/variables_spec.rb
describe 'Assignments' do
  describe 'using =' do
    describe 'evaluation order' do
      it 'evaluates expressions left to right when assignment with an accessor' do
        object = Object.new
        def object.a=(value) end
        ScratchPad.record []

        (ScratchPad << :receiver; object).a = (ScratchPad << :rhs; :value)
        ScratchPad.recorded.should == [:receiver, :rhs]
      end

      it 'evaluates expressions left to right when assignment with a #[]=' do
        object = Object.new
        def object.[]=(_, _) end
        ScratchPad.record []

        (ScratchPad << :receiver; object)[(ScratchPad << :argument; :a)] = (ScratchPad << :rhs; :value)
        ScratchPad.recorded.should == [:receiver, :argument, :rhs]
      end

      # similar tests for evaluation order are located in language/constants_spec.rb
      ruby_version_is ''...'3.2' do
        it 'evaluates expressions right to left when assignment with compounded constant' do
          m = Module.new
          ScratchPad.record []

          (ScratchPad << :module; m)::A = (ScratchPad << :rhs; :value)
          ScratchPad.recorded.should == [:rhs, :module]
        end
      end

      ruby_version_is '3.2' do
        it 'evaluates expressions left to right when assignment with compounded constant' do
          m = Module.new
          ScratchPad.record []

          (ScratchPad << :module; m)::A = (ScratchPad << :rhs; :value)
          ScratchPad.recorded.should == [:module, :rhs]
        end
      end

      it 'raises TypeError after evaluation of right-hand-side when compounded constant module is not a module' do
        ScratchPad.record []

        -> {
          (:not_a_module)::A = (ScratchPad << :rhs; :value)
        }.should raise_error(TypeError)

        ScratchPad.recorded.should == [:rhs]
      end
    end
  end

  describe 'using +=' do
    describe 'using an accessor' do
      before do
        klass = Class.new { attr_accessor :b }
        @a    = klass.new
      end

      it 'does evaluate receiver only once when assigns' do
        ScratchPad.record []
        @a.b = 1

        (ScratchPad << :evaluated; @a).b += 2

        ScratchPad.recorded.should == [:evaluated]
        @a.b.should == 3
      end

      it 'ignores method visibility when receiver is self' do
        klass_with_private_methods = Class.new do
          def initialize(n) @a = n end
          def public_method(n); self.a += n end
          private
          def a; @a end
          def a=(n) @a = n; 42 end
        end

        a = klass_with_private_methods.new(0)
        a.public_method(2).should == 2
      end
    end

    describe 'using a #[]' do
      before do
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

      it 'evaluates receiver only once when assigns' do
        ScratchPad.record []
        a = {k: 1}

        (ScratchPad << :evaluated; a)[:k] += 2

        ScratchPad.recorded.should == [:evaluated]
        a[:k].should == 3
      end

      it 'ignores method visibility when receiver is self' do
        klass_with_private_methods = Class.new do
          def initialize(h) @a = h end
          def public_method(k, n); self[k] += n end
          private
          def [](k) @a[k] end
          def []=(k, v) @a[k] = v; 42 end
        end

        a = klass_with_private_methods.new(k: 0)
        a.public_method(:k, 2).should == 2
      end

      context 'splatted argument' do
        it 'correctly handles it' do
          @b[:m] = 10
          (@b[*[:m]] += 10).should == 20
          @b[:m].should == 20

          @b[:n] = 10
          (@b[*(1; [:n])] += 10).should == 20
          @b[:n].should == 20

          @b[:k] = 10
          (@b[*begin 1; [:k] end] += 10).should == 20
          @b[:k].should == 20
        end

        it 'calls #to_a only once' do
          k = Object.new
          def k.to_a
            ScratchPad << :to_a
            [:k]
          end

          ScratchPad.record []
          @b[:k] = 10
          (@b[*k] += 10).should == 20
          @b[:k].should == 20
          ScratchPad.recorded.should == [:to_a]
        end

        it 'correctly handles a nested splatted argument' do
          @b[:k] = 10
          (@b[*[*[:k]]] += 10).should == 20
          @b[:k].should == 20
        end

        it 'correctly handles multiple nested splatted arguments' do
          klass_with_multiple_parameters = Class.new do
            def [](k1, k2, k3)
              @hash ||= {}
              @hash[:"#{k1}#{k2}#{k3}"]
            end

            def []=(k1, k2, k3, v)
              @hash ||= {}
              @hash[:"#{k1}#{k2}#{k3}"] = v
              7
            end
          end
          a = klass_with_multiple_parameters.new

          a[:a, :b, :c] = 10
          (a[*[:a], *[:b], *[:c]] += 10).should == 20
          a[:a, :b, :c].should == 20
        end
      end
    end

    describe 'using compounded constants' do
      it 'causes side-effects of the module part to be applied only once (when assigns)' do
        module ConstantSpecs
          OpAssignTrue = 1
        end

        suppress_warning do # already initialized constant
          x = 0
          (x += 1; ConstantSpecs)::OpAssignTrue += 2
          x.should == 1
          ConstantSpecs::OpAssignTrue.should == 3
        end

        ConstantSpecs.send :remove_const, :OpAssignTrue
      end
    end
  end
end

# generic cases
describe 'Multiple assignments' do
  it 'assigns multiple targets when assignment with an accessor' do
    object = Object.new
    class << object
      attr_accessor :a, :b
    end

    object.a, object.b = :a, :b

    object.a.should == :a
    object.b.should == :b
  end

  it 'assigns multiple targets when assignment with a nested accessor' do
    object = Object.new
    class << object
      attr_accessor :a, :b
    end

    (object.a, object.b), c = [:a, :b], nil

    object.a.should == :a
    object.b.should == :b
  end

  it 'assigns multiple targets when assignment with a #[]=' do
    object = Object.new
    class << object
      def []=(k, v) (@h ||= {})[k] = v; end
      def [](k) (@h ||= {})[k]; end
    end

    object[:a], object[:b] = :a, :b

    object[:a].should == :a
    object[:b].should == :b
  end

  it 'assigns multiple targets when assignment with a nested #[]=' do
    object = Object.new
    class << object
      def []=(k, v) (@h ||= {})[k] = v; end
      def [](k) (@h ||= {})[k]; end
    end

    (object[:a], object[:b]), c = [:v1, :v2], nil

    object[:a].should == :v1
    object[:b].should == :v2
  end

  it 'assigns multiple targets when assignment with compounded constant' do
    m = Module.new

    m::A, m::B = :a, :b

    m::A.should == :a
    m::B.should == :b
  end

  it 'assigns multiple targets when assignment with a nested compounded constant' do
    m = Module.new

    (m::A, m::B), c = [:a, :b], nil

    m::A.should == :a
    m::B.should == :b
  end
end

describe 'Multiple assignments' do
  describe 'evaluation order' do
    ruby_version_is ''...'3.1' do
      it 'evaluates expressions right to left when assignment with an accessor' do
        object = Object.new
        def object.a=(value) end
        ScratchPad.record []

        (ScratchPad << :a; object).a, (ScratchPad << :b; object).a = (ScratchPad << :c; :c), (ScratchPad << :d; :d)
        ScratchPad.recorded.should == [:c, :d, :a, :b]
      end

      it 'evaluates expressions right to left when assignment with a nested accessor' do
        object = Object.new
        def object.a=(value) end
        ScratchPad.record []

        ((ScratchPad << :a; object).a, foo), bar = [(ScratchPad << :b; :b)]
        ScratchPad.recorded.should == [:b, :a]
      end
    end

    ruby_version_is '3.1' do
      it 'evaluates expressions left to right when assignment with an accessor' do
        object = Object.new
        def object.a=(value) end
        ScratchPad.record []

        (ScratchPad << :a; object).a, (ScratchPad << :b; object).a = (ScratchPad << :c; :c), (ScratchPad << :d; :d)
        ScratchPad.recorded.should == [:a, :b, :c, :d]
      end

      it 'evaluates expressions left to right when assignment with a nested accessor' do
        object = Object.new
        def object.a=(value) end
        ScratchPad.record []

        ((ScratchPad << :a; object).a, foo), bar = [(ScratchPad << :b; :b)]
        ScratchPad.recorded.should == [:a, :b]
      end

      it 'evaluates expressions left to right when assignment with a deeply nested accessor' do
        o = Object.new
        def o.a=(value) end
        def o.b=(value) end
        def o.c=(value) end
        def o.d=(value) end
        def o.e=(value) end
        def o.f=(value) end
        ScratchPad.record []

        (ScratchPad << :a; o).a,
          ((ScratchPad << :b; o).b,
          ((ScratchPad << :c; o).c, (ScratchPad << :d; o).d),
          (ScratchPad << :e; o).e),
        (ScratchPad << :f; o).f = (ScratchPad << :value; :value)

        ScratchPad.recorded.should == [:a, :b, :c, :d, :e, :f, :value]
      end
    end

    ruby_version_is ''...'3.1' do
      it 'evaluates expressions right to left when assignment with a #[]=' do
        object = Object.new
        def object.[]=(_, _) end
        ScratchPad.record []

        (ScratchPad << :a; object)[(ScratchPad << :b; :b)], (ScratchPad << :c; object)[(ScratchPad << :d; :d)] = (ScratchPad << :e; :e), (ScratchPad << :f; :f)
        ScratchPad.recorded.should == [:e, :f, :a, :b, :c, :d]
      end

      it 'evaluates expressions right to left when assignment with a nested #[]=' do
        object = Object.new
        def object.[]=(_, _) end
        ScratchPad.record []

        ((ScratchPad << :a; object)[(ScratchPad << :b; :b)], foo), bar = [(ScratchPad << :c; :c)]
        ScratchPad.recorded.should == [:c, :a, :b]
      end
    end

    ruby_version_is '3.1' do
      it 'evaluates expressions left to right when assignment with a #[]=' do
        object = Object.new
        def object.[]=(_, _) end
        ScratchPad.record []

        (ScratchPad << :a; object)[(ScratchPad << :b; :b)], (ScratchPad << :c; object)[(ScratchPad << :d; :d)] = (ScratchPad << :e; :e), (ScratchPad << :f; :f)
        ScratchPad.recorded.should == [:a, :b, :c, :d, :e, :f]
      end

      it 'evaluates expressions left to right when assignment with a nested #[]=' do
        object = Object.new
        def object.[]=(_, _) end
        ScratchPad.record []

        ((ScratchPad << :a; object)[(ScratchPad << :b; :b)], foo), bar = [(ScratchPad << :c; :c)]
        ScratchPad.recorded.should == [:a, :b, :c]
      end

      it 'evaluates expressions left to right when assignment with a deeply nested #[]=' do
        o = Object.new
        def o.[]=(_, _) end
        ScratchPad.record []

        (ScratchPad << :ra; o)[(ScratchPad << :aa; :aa)],
          ((ScratchPad << :rb; o)[(ScratchPad << :ab; :ab)],
          ((ScratchPad << :rc; o)[(ScratchPad << :ac; :ac)], (ScratchPad << :rd; o)[(ScratchPad << :ad; :ad)]),
          (ScratchPad << :re; o)[(ScratchPad << :ae; :ae)]),
        (ScratchPad << :rf; o)[(ScratchPad << :af; :af)] = (ScratchPad << :value; :value)

        ScratchPad.recorded.should == [:ra, :aa, :rb, :ab, :rc, :ac, :rd, :ad, :re, :ae, :rf, :af, :value]
      end
    end

    ruby_version_is ''...'3.2' do
      it 'evaluates expressions right to left when assignment with compounded constant' do
        m = Module.new
        ScratchPad.record []

        (ScratchPad << :a; m)::A, (ScratchPad << :b; m)::B = (ScratchPad << :c; :c), (ScratchPad << :d; :d)
        ScratchPad.recorded.should == [:c, :d, :a, :b]
      end
    end

    ruby_version_is '3.2' do
      it 'evaluates expressions left to right when assignment with compounded constant' do
        m = Module.new
        ScratchPad.record []

        (ScratchPad << :a; m)::A, (ScratchPad << :b; m)::B = (ScratchPad << :c; :c), (ScratchPad << :d; :d)
        ScratchPad.recorded.should == [:a, :b, :c, :d]
      end

      it 'evaluates expressions left to right when assignment with a nested compounded constant' do
        m = Module.new
        ScratchPad.record []

        ((ScratchPad << :a; m)::A, foo), bar = [(ScratchPad << :b; :b)]
        ScratchPad.recorded.should == [:a, :b]
      end

      it 'evaluates expressions left to right when assignment with deeply nested compounded constants' do
        m = Module.new
        ScratchPad.record []

        (ScratchPad << :a; m)::A,
          ((ScratchPad << :b; m)::B,
          ((ScratchPad << :c; m)::C, (ScratchPad << :d; m)::D),
          (ScratchPad << :e; m)::E),
        (ScratchPad << :f; m)::F = (ScratchPad << :value; :value)

        ScratchPad.recorded.should == [:a, :b, :c, :d, :e, :f, :value]
      end
    end
  end

  context 'when assignment with method call and receiver is self' do
    it 'assigns values correctly when assignment with accessor' do
      object = Object.new
      class << object
        attr_accessor :a, :b

        def assign(v1, v2)
          self.a, self.b = v1, v2
        end
      end

      object.assign :v1, :v2
      object.a.should == :v1
      object.b.should == :v2
    end

    it 'evaluates expressions right to left when assignment with a nested accessor' do
      object = Object.new
      class << object
        attr_accessor :a, :b

        def assign(v1, v2)
          (self.a, self.b), c = [v1, v2], nil
        end
      end

      object.assign :v1, :v2
      object.a.should == :v1
      object.b.should == :v2
    end

    it 'assigns values correctly when assignment with a #[]=' do
      object = Object.new
      class << object
        def []=(key, v)
          @h ||= {}
          @h[key] = v
        end

        def [](key)
          (@h || {})[key]
        end

        def assign(k1, v1, k2, v2)
          self[k1], self[k2] = v1, v2
        end
      end

      object.assign :k1, :v1, :k2, :v2
      object[:k1].should == :v1
      object[:k2].should == :v2
    end

    it 'assigns values correctly when assignment with a nested #[]=' do
      object = Object.new
      class << object
        def []=(key, v)
          @h ||= {}
          @h[key] = v
        end

        def [](key)
          (@h || {})[key]
        end

        def assign(k1, v1, k2, v2)
          (self[k1], self[k2]), c = [v1, v2], nil
        end
      end

      object.assign :k1, :v1, :k2, :v2
      object[:k1].should == :v1
      object[:k2].should == :v2
    end

    it 'assigns values correctly when assignment with compounded constant' do
      m = Module.new
      m.module_exec do
        self::A, self::B = :v1, :v2
      end

      m::A.should == :v1
      m::B.should == :v2
    end

    it 'assigns values correctly when assignment with a nested compounded constant' do
      m = Module.new
      m.module_exec do
        (self::A, self::B), c = [:v1, :v2], nil
      end

      m::A.should == :v1
      m::B.should == :v2
    end
  end
end
