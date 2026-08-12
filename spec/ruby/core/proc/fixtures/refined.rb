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
end
