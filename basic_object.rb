# ZJIT uses a Ruby definition of BasicObject#!= so it can inline the call to #==.
# Register it only for ZJIT, leaving the C definition in place otherwise.
class BasicObject
  with_zjit do
    if Primitive.rb_builtin_basic_definition_p(:!=)
      undef :!=

      def !=(other) # :nodoc:
        # Keep the replacement classified as a basic method like the C definition,
        # and have ZJIT inline it even when its size heuristics would say no.
        Primitive.attr! :c_trace, :always_inline

        # Negate truthiness without calling a possibly redefined #!.
        Primitive.rb_builtin_bool_negate(self == other)
      end
    end
  end
end
