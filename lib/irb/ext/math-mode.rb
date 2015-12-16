# frozen_string_literal: false
#
#   math-mode.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#
require "mathn"

module IRB
  class Context
    # Returns whether bc mode is enabled.
    #
    # See #math_mode=
    attr_reader :math_mode
    # Alias for #math_mode
    alias math? math_mode

    # Sets bc mode, which loads +lib/mathn.rb+ so fractions or matrix are
    # available.
    #
    # Also available as the +-m+ command line option.
    #
    # See IRB@Command+line+options and the unix manpage <code>bc(1)</code> for
    # more information.
    def math_mode=(opt)
      if @math_mode == true && !opt
        IRB.fail CantReturnToNormalMode
        return
      end

      @math_mode = opt
      if math_mode
        main.extend Math
        print "start math mode\n" if verbose?
      end
    end

    def inspect?
      @inspect_mode.nil? && !@math_mode or @inspect_mode
    end
  end
end

