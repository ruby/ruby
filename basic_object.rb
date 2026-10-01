# ZJIT uses a Ruby definition of BasicObject#!= so it can inline the call to #==.
# Register it only for ZJIT, leaving the C definition in place otherwise.
class BasicObject
  with_zjit do
    if Primitive.rb_builtin_basic_definition_p(:!=)
      undef :!=

      def !=(other) # :nodoc:
        # Keep the replacement classified as a basic method like the C definition.
        Primitive.attr! :c_trace

        # Calling #! on the result would allow a redefinition to change the answer.
        if self == other
          false
        else
          true
        end
      end
    end
  end
end
