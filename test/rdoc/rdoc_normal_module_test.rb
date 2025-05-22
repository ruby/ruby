# frozen_string_literal: true
require_relative 'xref_test_case'

class RDocNormalModuleTest < XrefTestCase

  def setup
    super

    @mod = RDoc::NormalModule.new 'Mod'
  end

  def test_ancestors_module
    top_level = @store.add_file 'file.rb'
    mod = top_level.add_module RDoc::NormalModule, 'Mod'
    incl = RDoc::Include.new 'Incl', ''

    mod.add_include incl

    assert_equal [incl.name], mod.ancestors

    mod2 = top_level.add_module RDoc::NormalModule, 'Inc2'
    inc2 = RDoc::Include.new 'Inc2', ''
    mod.add_include inc2
    assert_equal [mod2, incl.name], mod.ancestors
  end

  def test_aref
    assert_equal 'module-M1',     @m1.aref
    assert_equal 'module-M1::M2', @m1_m2.aref
  end

  def test_definition
    m = RDoc::NormalModule.new 'M'

    assert_equal 'module M', m.definition
  end

  def test_module_eh
    assert @mod.module?
  end

end
