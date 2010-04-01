require File.expand_path '../xref_test_case', __FILE__

class TestRDocNormalModule < XrefTestCase

  def setup
    super

    @mod = RDoc::NormalModule.new 'Mod'
  end

  def test_ancestors_module
    top_level = RDoc::TopLevel.new 'file.rb'
    mod = top_level.add_module RDoc::NormalModule, 'Mod'
    incl = RDoc::Include.new 'Incl', ''

    mod.add_include incl

    assert_equal [incl], mod.ancestors
  end

  def test_module_eh
    assert @mod.module?
  end

end

