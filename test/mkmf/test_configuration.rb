# frozen_string_literal: false
require_relative 'base'

class TestMkmfConfiguration < TestMkmf
  def test_verbose_with_rbconfig_verbose_disabled
    makefile = mkmf do
      self.class::CONFIG['MKMF_VERBOSE'] = "0"
      init_mkmf(self.class::CONFIG)
      configuration '.'
    end
    verbose = makefile.grep(/^V =/).first[/^V = (.)$/, 1]

    assert_equal "0", verbose
  end

  def test_verbose_with_rbconfig_verbose_enabled
    makefile = mkmf do
      self.class::CONFIG['MKMF_VERBOSE'] = "1"
      init_mkmf(self.class::CONFIG)
      configuration '.'
    end
    verbose = makefile.grep(/^V =/).first[/^V = (.)$/, 1]

    assert_equal "1", verbose
  end

  def test_verbose_with_arg
    assert_separately([], %w[--with-verbose], <<-'end;')
      makefile = mkmf do
        self.class::CONFIG['MKMF_VERBOSE'] = "0"
        init_mkmf(self.class::CONFIG)
        configuration '.'
      end
      verbose = makefile.grep(/^V =/).first[/^V = (.)$/, 1]

      assert_equal "1", verbose
    end;
  end
end
