#!/usr/bin/env ruby
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++


require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/dependency_list'

class TestGemDependencyList < RubyGemTestCase

  def setup
    super

    @deplist = Gem::DependencyList.new

    @a1 = quick_gem 'a', '1'
    @a2 = quick_gem 'a', '2'
    @a3 = quick_gem 'a', '3'

    @b1 = quick_gem 'b', '1' do |s| s.add_dependency 'a', '>= 1' end
    @b2 = quick_gem 'b', '2' do |s| s.add_dependency 'a', '>= 1' end

    @c1 = quick_gem 'c', '1' do |s| s.add_dependency 'b', '>= 1' end
    @c2 = quick_gem 'c', '2'

    @d1 = quick_gem 'd', '1' do |s| s.add_dependency 'c', '>= 1' end
  end

  def test_self_from_source_index
    hash = {
      'a-1' => @a1,
      'b-2' => @b2,
    }

    si = Gem::SourceIndex.new hash
    deps = Gem::DependencyList.from_source_index si

    assert_equal %w[b-2 a-1], deps.dependency_order.map { |s| s.full_name }
  end

  def test_active_count
    assert_equal 0, @deplist.send(:active_count, [], {})
    assert_equal 1, @deplist.send(:active_count, [@a1], {})
    assert_equal 0, @deplist.send(:active_count, [@a1],
                                  { @a1.full_name => true })
  end

  def test_add
    assert_equal [], @deplist.dependency_order

    @deplist.add @a1, @b2

    assert_equal [@b2, @a1], @deplist.dependency_order
  end

  def test_dependency_order
    @deplist.add @a1, @b1, @c1, @d1

    order = @deplist.dependency_order

    assert_equal %w[d-1 c-1 b-1 a-1], order.map { |s| s.full_name }
  end

  def test_dependency_order_circle
    @a1.add_dependency 'c', '>= 1'
    @deplist.add @a1, @b1, @c1

    order = @deplist.dependency_order

    assert_equal %w[b-1 c-1 a-1], order.map { |s| s.full_name }
  end

  def test_dependency_order_diamond
    util_diamond
    e1 = quick_gem 'e', '1'
    @deplist.add e1
    @a1.add_dependency 'e', '>= 1'

    order = @deplist.dependency_order

    assert_equal %w[d-1 c-2 b-1 a-2 e-1], order.map { |s| s.full_name },
                 'deps of trimmed specs not included'
  end

  def test_dependency_order_no_dependendencies
    @deplist.add @a1, @c2

    order = @deplist.dependency_order

    assert_equal %w[c-2 a-1], order.map { |s| s.full_name }
  end

  def test_find_name
    @deplist.add @a1, @b2

    assert_equal "a-1", @deplist.find_name("a-1").full_name
    assert_equal "b-2", @deplist.find_name("b-2").full_name

    assert_nil @deplist.find_name("c-2")
  end

  def test_ok_eh
    assert @deplist.ok?, 'no dependencies'

    @deplist.add @b2

    assert ! @deplist.ok?, 'unsatisfied dependency'

    @deplist.add @a1

    assert @deplist.ok?, 'satisfied dependency'
  end

  def test_ok_eh_mismatch
    a1 = quick_gem 'a', '1'
    a2 = quick_gem 'a', '2'

    b = quick_gem 'b', '1' do |s| s.add_dependency 'a', '= 1' end
    c = quick_gem 'c', '1' do |s| s.add_dependency 'a', '= 2' end

    d = quick_gem 'd', '1' do |s|
      s.add_dependency 'b'
      s.add_dependency 'c'
    end

    @deplist.add a1, a2, b, c, d

    assert @deplist.ok?, 'this will break on require'
  end

  def test_ok_eh_redundant
    @deplist.add @a1, @a3, @b2

    @deplist.remove_by_name("a-1")

    assert @deplist.ok?
  end

  def test_ok_to_remove_eh
    @deplist.add @a1

    assert @deplist.ok_to_remove?("a-1")

    @deplist.add @b2

    assert ! @deplist.ok_to_remove?("a-1")

    @deplist.add @a2

    assert @deplist.ok_to_remove?("a-1")
    assert @deplist.ok_to_remove?("a-2")
    assert @deplist.ok_to_remove?("b-2")
  end

  def test_ok_to_remove_eh_after_sibling_removed
    @deplist.add @a1, @a2, @b2

    assert @deplist.ok_to_remove?("a-1")
    assert @deplist.ok_to_remove?("a-2")

    @deplist.remove_by_name("a-1")

    assert ! @deplist.ok_to_remove?("a-2")
  end

  def test_remove_by_name
    @deplist.add @a1, @b2

    @deplist.remove_by_name "a-1"

    assert ! @deplist.ok?
  end

  def test_tsort_each_node
    util_diamond

    order = %w[a-1 a-2 b-1 c-2 d-1]

    @deplist.tsort_each_node do |node|
      assert_equal order.shift, node.full_name
    end

    assert order.empty?
  end

  def test_tsort_each_child
    util_diamond

    order = %w[a-2]

    @deplist.tsort_each_child(@b1) do |node|
      assert_equal order.shift, node.full_name
    end

    assert order.empty?
  end

  # d1 -> b1 -> a1
  # d1 -> c2 -> a2
  def util_diamond
    @c2.add_dependency 'a', '>= 2'
    @d1.add_dependency 'b'

    @deplist.add @a1, @a2, @b1, @c2, @d1
  end

end

