module Lrama
  class Grammar
    class Code
      class NoReferenceCode < Code
        private

        # * ($$) error
        # * (@$) error
        # * ($:$) error
        # * ($1) error
        # * (@1) error
        # * ($:1) error
        def reference_to_c(ref)
          case
          when ref.type == :dollar # $$, $n
            raise "$#{ref.value} can not be used in #{type}."
          when ref.type == :at # @$, @n
            raise "@#{ref.value} can not be used in #{type}."
          when ref.type == :index # $:$, $:n
            raise "$:#{ref.value} can not be used in #{type}."
          else
            raise "Unexpected. #{self}, #{ref}"
          end
        end
      end
    end
  end
end
