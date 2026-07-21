module ProcRefinedSpecs
  module StringShout
    refine String do
      def shout
        upcase + "!"
      end
    end
  end

  # Refines the same String#shout as StringShout, plus its own #quiet, so
  # specs can observe both which module wins for a conflicting method and
  # that all given modules are activated.
  module StringQuiet
    refine String do
      def shout
        downcase
      end

      def quiet
        "..."
      end
    end
  end

  # Refines operators and element access, including Hash#[] with a String
  # key, so specs can check the specialized call paths implementations use
  # for them.
  module Operators
    refine Integer do
      def +(other)
        "plus(#{self},#{other})"
      end

      def <(other)
        "lt"
      end
    end

    refine Array do
      def [](i)
        "at#{i}"
      end
    end

    refine Hash do
      def [](k)
        "aref(#{k})"
      end
    end
  end
end
