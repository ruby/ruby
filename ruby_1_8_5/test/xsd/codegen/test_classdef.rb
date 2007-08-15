require 'test/unit'
require 'xsd/codegen/classdef'


module XSD; module CodeGen


class TestClassDefCreator < Test::Unit::TestCase
  include XSD::CodeGen
  include GenSupport

  def test_classdef_simple
    c = ClassDef.new("Foo")
    assert_equal(format(<<-EOD), c.dump)
      class Foo
      end
    EOD
  end

  def test_classdef_complex
    c = ClassDef.new("Foo::Bar::Baz", String)
    assert_equal(format(<<-EOD), c.dump)
      module Foo; module Bar

      class Baz < String
      end

      end; end
    EOD
  end

  def test_require
    c = ClassDef.new("Foo")
    c.def_require("foo/bar")
    assert_equal(format(<<-EOD), c.dump)
      require 'foo/bar'

      class Foo
      end
    EOD
  end

  def test_comment
    c = ClassDef.new("Foo")
    c.def_require("foo/bar")
    c.comment = <<-EOD
      foo
    EOD
    assert_equal(format(<<-EOD), c.dump)
      require 'foo/bar'

      # foo
      class Foo
      end
    EOD
    c.comment = <<-EOD
            foo

              bar
             baz

    EOD
    assert_equal(format(<<-EOD), c.dump)
      require 'foo/bar'

      # foo
      # 
      #   bar
      #  baz
      # 
      class Foo
      end
    EOD
  end

  def test_emptymethod
    c = ClassDef.new("Foo")
    c.def_method('foo') do
    end
    c.def_method('bar') do
      ''
    end
    assert_equal(format(<<-EOD), c.dump)
      class Foo
        def foo
        end

        def bar
        end
      end
    EOD
  end

  def test_full
    c = ClassDef.new("Foo::Bar::HobbitName", String)
    c.def_require("foo/bar")
    c.comment = <<-EOD
        foo
      bar
        baz
    EOD
    c.def_const("FOO", 1)
    c.def_classvar("@@foo", "var".dump)
    c.def_classvar("baz", "1".dump)
    c.def_attr("Foo", true, "foo")
    c.def_attr("bar")
    c.def_attr("baz", true)
    c.def_attr("Foo2", true, "foo2")
    c.def_attr("foo3", false, "foo3")
    c.def_method("foo") do
      <<-EOD
        foo.bar = 1
\tbaz.each do |ele|
\t  ele
        end
      EOD
    end
    c.def_method("baz", "qux") do
      <<-EOD
        [1, 2, 3].each do |i|
          p i
        end
      EOD
    end

    m = MethodDef.new("qux", "quxx", "quxxx") do
      <<-EOD
      p quxx + quxxx
      EOD
    end
    m.comment = "hello world\n123"
    c.add_method(m)
    c.def_code <<-EOD
      Foo.new
      Bar.z
    EOD
    c.def_code <<-EOD
      Foo.new
      Bar.z
    EOD
    c.def_privatemethod("foo", "baz", "*arg", "&block")

    assert_equal(format(<<-EOD), c.dump)
    require 'foo/bar'

    module Foo; module Bar

    #   foo
    # bar
    #   baz
    class HobbitName < String
      @@foo = "var"
      @@baz = "1"

      FOO = 1

      Foo.new
      Bar.z

      Foo.new
      Bar.z

      attr_accessor :bar
      attr_accessor :baz
      attr_reader :foo3

      def Foo
        @foo
      end

      def Foo=(value)
        @foo = value
      end

      def Foo2
        @foo2
      end

      def Foo2=(value)
        @foo2 = value
      end

      def foo
        foo.bar = 1
        baz.each do |ele|
          ele
        end
      end

      def baz(qux)
        [1, 2, 3].each do |i|
          p i
        end
      end

      # hello world
      # 123
      def qux(quxx, quxxx)
        p quxx + quxxx
      end

    private

      def foo(baz, *arg, &block)
      end
    end

    end; end
    EOD
  end
end


end; end
