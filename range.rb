class Range
  with_jit do
    if Primitive.rb_builtin_basic_definition_p(:each)
      undef :each

      def each # :nodoc:
        Primitive.attr! :inline_block, :c_trace, :without_interrupts

        unless defined?(yield)
          return Primitive.cexpr! 'SIZED_ENUMERATOR(self, 0, 0, range_enum_size)'
        end

        if Primitive.rb_builtin_range_fixnum_p
          i = Primitive.rb_builtin_range_begin
          hi = Primitive.rb_builtin_range_rev_start
          until Primitive.rb_builtin_fixnum_above(i, hi)
            yield i
            i = Primitive.rb_builtin_fixnum_inc_checked(i)
          end
        else
          Primitive.rb_builtin_range_each_fallback
        end
        self
      end
    end

    if Primitive.rb_builtin_basic_definition_p(:reverse_each)
      undef :reverse_each

      def reverse_each # :nodoc:
        Primitive.attr! :inline_block, :c_trace, :without_interrupts

        unless defined?(yield)
          return Primitive.cexpr! 'SIZED_ENUMERATOR(self, 0, 0, range_enum_reverse_size)'
        end

        if Primitive.rb_builtin_range_fixnum_p
          i = Primitive.rb_builtin_range_rev_start
          lo = Primitive.rb_builtin_range_begin
          until Primitive.rb_builtin_fixnum_below(i, lo)
            yield i
            i = Primitive.rb_builtin_fixnum_dec(i)
          end
        elsif Primitive.rb_builtin_range_generic_p
          # Integer-family bounds beyond the fixnum fast path, and the
          # endless-range TypeError, replicated bit for bit in C.
          Primitive.rb_builtin_range_reverse_each_generic
        else
          # Non-integer ranges take Enumerable#reverse_each, exactly like
          # the C implementation's rb_call_super branch.
          return super
        end
        self
      end
    end
  end
end
