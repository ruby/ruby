# frozen_string_literal: true
require_relative 'xref_test_case'

class TestRDocExtend < XrefTestCase

  def setup
    super

    @ext = RDoc::Extend.new 'M1', 'comment'
    @ext.parent = @m1
    @ext.store = @store
  end

  def test_module
    assert_equal @m1, @ext.module
    assert_equal 'Unknown', RDoc::Extend.new('Unknown', 'comment').module
  end

  def test_module_extended
    m1 = @xref_data.add_module RDoc::NormalModule, 'Mod1'
                  m1.add_module RDoc::NormalModule, 'Mod3'
    m1_m2       = m1.add_module RDoc::NormalModule, 'Mod2'
    m1_m2_m3    = m1_m2.add_module RDoc::NormalModule, 'Mod3'
                  m1_m2_m3.add_module RDoc::NormalModule, 'Mod4'
                  m1_m2.add_module RDoc::NormalModule, 'Mod4'
    m1_m2_k0    = m1_m2.add_class RDoc::NormalClass, 'Klass0'
    m1_m2_k0_m4 = m1_m2_k0.add_module RDoc::NormalModule, 'Mod4'
                  m1_m2_k0_m4.add_module RDoc::NormalModule, 'Mod6'
                  m1_m2_k0.add_module RDoc::NormalModule, 'Mod5'

    e0_m4 = RDoc::Extend.new 'Mod4', nil
    e0_m5 = RDoc::Extend.new 'Mod5', nil
    e0_m6 = RDoc::Extend.new 'Mod6', nil
    e0_m1 = RDoc::Extend.new 'Mod1', nil
    e0_m2 = RDoc::Extend.new 'Mod2', nil
    e0_m3 = RDoc::Extend.new 'Mod3', nil

    m1_m2_k0.add_extend e0_m4
    m1_m2_k0.add_extend e0_m5
    m1_m2_k0.add_extend e0_m6
    m1_m2_k0.add_extend e0_m1
    m1_m2_k0.add_extend e0_m2
    m1_m2_k0.add_extend e0_m3

    assert_equal [e0_m4, e0_m5, e0_m6, e0_m1, e0_m2, e0_m3], m1_m2_k0.extends
    assert_equal [@object, 'BasicObject'], m1_m2_k0.ancestors

    m1_k1 = m1.add_class RDoc::NormalClass, 'Klass1'

    e1_m1 = RDoc::Extend.new 'Mod1', nil
    e1_m2 = RDoc::Extend.new 'Mod2', nil
    e1_m3 = RDoc::Extend.new 'Mod3', nil
    e1_m4 = RDoc::Extend.new 'Mod4', nil
    e1_k0_m4 = RDoc::Extend.new 'Klass0::Mod4', nil

    m1_k1.add_extend e1_m1
    m1_k1.add_extend e1_m2
    m1_k1.add_extend e1_m3
    m1_k1.add_extend e1_m4
    m1_k1.add_extend e1_k0_m4

    assert_equal [e1_m1, e1_m2, e1_m3, e1_m4, e1_k0_m4], m1_k1.extends
    assert_equal [@object, 'BasicObject'], m1_k1.ancestors

    m1_k2 = m1.add_class RDoc::NormalClass, 'Klass2'

    e2_m1 = RDoc::Extend.new 'Mod1', nil
    e2_m2 = RDoc::Extend.new 'Mod2', nil
    e2_m3 = RDoc::Extend.new 'Mod3', nil
    e2_k0_m4 = RDoc::Extend.new 'Klass0::Mod4', nil

    m1_k2.add_extend e2_m1
    m1_k2.add_extend e2_m3
    m1_k2.add_extend e2_m2
    m1_k2.add_extend e2_k0_m4

    assert_equal [e2_m1, e2_m3, e2_m2, e2_k0_m4], m1_k2.extends
    assert_equal [@object, 'BasicObject'], m1_k2.ancestors

    m1_k3 = m1.add_class RDoc::NormalClass, 'Klass3'

    e3_m1 = RDoc::Extend.new 'Mod1', nil
    e3_m2 = RDoc::Extend.new 'Mod2', nil
    e3_m4 = RDoc::Extend.new 'Mod4', nil

    m1_k3.add_extend e3_m1
    m1_k3.add_extend e3_m2
    m1_k3.add_extend e3_m4

    assert_equal [e3_m1, e3_m2, e3_m4], m1_k3.extends
    assert_equal [@object, 'BasicObject'], m1_k3.ancestors
  end

end
