# frozen_string_literal: false
require_relative 'base'

class TestMkmf
  class TestFlags < TestMkmf
    def test_valid_warnflags
      val = $extmk
      warnflags = $warnflags
      makefile = mkmf do
        $extmk = false
        self.class::CONFIG['warnflags'] = %w"-Wextra
        -Wno-unused-parameter -Wno-parentheses -Wno-long-long
        -Wno-missing-field-initializers -Werror=pointer-arith
        -Werror=write-strings -Werror=declaration-after-statement
        -Werror=shorten-64-to-32
        -Werror-implicit-function-declaration
        ".join(' ')
        self.class::CONFIG['GCC'] = 'yes'
        init_mkmf(self.class::CONFIG)
        configuration '.'
      end
      generated_flags = makefile.grep(/warnflags/).first[/^warnflags = (.*)$/, 1].split

      assert_equal %w"
      -Wextra -Wno-unused-parameter -Wno-parentheses
      -Wno-long-long -Wno-missing-field-initializers -Wpointer-arith
      -Wwrite-strings -Wdeclaration-after-statement
      -Wshorten-64-to-32 -Wimplicit-function-declaration
      ", generated_flags

    ensure
      $warnflags = warnflags
      $extmk = val
    end

    def test_try_ldflag_invalid_opt
      assert_separately([], <<-'end;') #do
        assert(!try_ldflags("nosuch.c"), TestMkmf::MKMFLOG)
        assert(have_devel?, TestMkmf::MKMFLOG)
      end;
    end

    def test_try_cflag_invalid_opt
      assert_separately([], <<-'end;') #do
        assert(!try_cflags("nosuch.c"), TestMkmf::MKMFLOG)
        assert(have_devel?, TestMkmf::MKMFLOG)
      end;
    end

    def test_try_cppflag_invalid_opt
      assert_separately([], <<-'end;') #do
        assert(!try_cppflags("nosuch.c"), TestMkmf::MKMFLOG)
        assert(have_devel?, TestMkmf::MKMFLOG)
      end;
    end
  end
end
