# frozen_string_literal: false
require_relative 'base'
require 'tempfile'

class TestMkmfHaveFunc < TestMkmf
  def test_have_func
    assert_equal(true, have_func("ruby_init"), MKMFLOG)
    assert_include($defs, '-DHAVE_RUBY_INIT')
  end

  def test_have_func_without_headers_uses_link_fallback
    object = create_link_only_func("mkmf_link_only")
    assert_equal(true, have_func("mkmf_link_only", nil, object), MKMFLOG)
    assert_include($defs, '-DHAVE_MKMF_LINK_ONLY')
  end

  def test_have_func_with_headers_requires_declaration
    object = create_link_only_func("mkmf_link_only")
    assert_equal(false, have_func("mkmf_link_only", "stdio.h", object), MKMFLOG)
    assert_not_include($defs, '-DHAVE_MKMF_LINK_ONLY')
  end

  def test_have_func_with_headers_accepts_declaration
    assert_equal(true, have_func("printf", "stdio.h"), MKMFLOG)
    assert_include($defs, '-DHAVE_PRINTF')
  end

  def test_not_have_func
    assert_equal(false, have_func("no_ruby_init"), MKMFLOG)
    assert_not_include($defs, '-DHAVE_RUBY_INIT')
  end

  private

  def create_link_only_func(name)
    object = "#{name}.#{$OBJEXT}"
    create_tmpsrc("void #{name}(void) {}\n")
    assert(xsystem(cc_command), "compile failed: #{cc_command}")
    File.rename("#{CONFTEST}.#{$OBJEXT}", object)
    object
  end
end
