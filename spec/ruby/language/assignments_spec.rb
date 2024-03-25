require_relative '../spec_helper'

# Should be synchronized with spec/ruby/language/optional_assignments_spec.rb
describe 'Assignments' do
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
