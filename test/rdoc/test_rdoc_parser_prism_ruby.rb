# frozen_string_literal: true

require_relative 'helper'
require 'rdoc/parser'
require 'rdoc/parser/prism_ruby'

module RDocParserPrismTestCases
  def setup
    super

    @tempfile = Tempfile.new self.class.name
    @filename = @tempfile.path

    @top_level = @store.add_file @filename

    @options = RDoc::Options.new
    @options.quiet = true
    @options.option_parser = OptionParser.new

    @comment = RDoc::Comment.new '', @top_level

    @stats = RDoc::Stats.new @store, 0
  end

  def teardown
    super

    @tempfile.close!
  end

  def test_look_for_directives_in_section
    util_parser <<~RUBY
      # :section: new section
    RUBY
    section = @top_level.current_section
    assert_equal 'new section', section.title
  end

  def test_look_for_directives_in_commented
    util_parser <<~RUBY
      # how to make a section:
      # # :section: new section
    RUBY
    section = @top_level.current_section
    assert_nil   section.title
  end

  def test_look_for_directives_in_unhandled
    util_parser <<~RUBY
      # :unhandled: blah
    RUBY
    assert_equal 'blah', @top_level.metadata['unhandled']
  end

  def test_block_comment
    util_parser <<~RUBY
      =begin rdoc
      foo
      =end
      class A
      =begin
      bar
      baz
      =end
        def f; end
      end
    RUBY
    klass = @top_level.classes.first
    meth = klass.method_list.first
    assert_equal 'foo', klass.comment.text.strip
    assert_equal "bar\nbaz", meth.comment.text.strip
  end

  def test_module
    util_parser <<~RUBY
      # my module
      module Foo
      end
    RUBY
    mod = @top_level.modules.first
    assert_equal 'Foo', mod.full_name
    assert_equal 'my module', mod.comment.text
    assert_equal [@top_level], mod.in_files
  end

  def test_nested_module_with_colon
    util_parser <<~RUBY
      module Foo
        module Bar; end
        module Bar::Baz1; end
        module ::Foo
          module Bar2; end
        end
      end
      module ::Baz; end
      module Foo::Bar::Baz2
        module ::Foo2
          module Bar; end
        end
        module Blah; end
      end
    RUBY
    module_names = @store.all_modules.map(&:full_name)
    expected = %w[
      Foo Foo::Bar Foo::Bar::Baz1 Foo::Bar2 Baz Foo::Bar::Baz2 Foo2 Foo2::Bar Foo::Bar::Baz2::Blah
    ]
    assert_equal expected.sort, module_names.sort
  end

  def test_class
    util_parser <<~RUBY
      # my class
      class Foo
      end
    RUBY
    klass = @top_level.classes.first
    assert_equal 'Foo', klass.full_name
    assert_equal 'my class', klass.comment.text
    assert_equal [@top_level], klass.in_files
    assert_equal 2, klass.line
  end

  def test_nested_class_with_colon
    util_parser <<~RUBY
      class Foo
        class Bar; end
        class Bar::Baz1; end
        class ::Foo
          class Bar2; end
        end
      end
      class ::Baz; end
      class Foo::Bar::Baz2
        class ::Foo2
          class Bar; end
        end
        class Blah; end
      end
    RUBY
    class_names = @store.all_classes.map(&:full_name)
    expected = %w[
      Foo Foo::Bar Foo::Bar::Baz1 Foo::Bar2 Baz Foo::Bar::Baz2 Foo2 Foo2::Bar Foo::Bar::Baz2::Blah
    ]
    assert_equal expected.sort, class_names.sort
  end

  def test_open_class_with_superclass
    util_parser <<~RUBY
      class A; end

      class B < A
        def m1; end
      end

      class B < A
        def m2; end
      end

      class C < String
        def m1; end
      end

      class C < String
        def m2; end
      end
    RUBY
    classes = @top_level.classes
    assert_equal 3, classes.size
    _a, b, c = classes
    assert_equal 'A', b.superclass.full_name
    assert_equal 'String', c.superclass
    assert_equal ['m1', 'm2'], b.method_list.map(&:name)
    assert_equal ['m1', 'm2'], c.method_list.map(&:name)
  end

  def test_confusing_superclass
    util_parser <<~RUBY
      module A
        class B; end
      end

      module A
        class C1 < A::B; end
      end

      class A::C2 < A::B; end

      module A::A
        class B; end
      end

      module A
        class C3 < A::B; end
      end

      class A::C4 < A::B; end
    RUBY
    mod = @top_level.modules.first
    classes = mod.classes
    assert_equal ['A::B', 'A::C1', 'A::C2', 'A::C3', 'A::C4'], classes.map(&:full_name)
    assert_equal ['A::B', 'A::B', 'A::A::B', 'A::B'], classes.drop(1).map(&:superclass).map(&:full_name)
  end

  def test_class_module_nodoc
    util_parser <<~RUBY
      class Foo # :nodoc:
      end

      class Bar
      end # :nodoc:

      class Baz; end

      class Baz::A; end # :nodoc:

      module MFoo # :nodoc:
      end

      module MBar
      end # :nodoc:

      module MBaz; end

      module MBaz::M; end; # :nodoc:
    RUBY
    documentables = @store.all_classes_and_modules.select(&:document_self)
    assert_equal ['Baz', 'MBaz'], documentables.map(&:full_name) unless accept_legacy_bug?
  end

  def test_class_module_stopdoc
    util_parser <<~RUBY
      # comment
      class Foo
        class A; end
        # :stopdoc:
        class B; end
      end

      # comment
      module Bar
        module A; end
        # :stopdoc:
        module B; end
      end
    RUBY
    klass = @top_level.classes.first
    mod = @top_level.modules.first
    assert_equal 'comment', klass.comment.text.strip
    assert_equal 'comment', mod.comment.text.strip
    assert_equal ['Foo::A'], klass.classes.select(&:document_self).map(&:full_name)
    assert_equal ['Bar::A'], mod.modules.select(&:document_self).map(&:full_name)
  end

  def test_class_superclass
    util_parser <<~RUBY
      class Foo; end
      class Bar < Foo
      end
      class Baz < (any expression)
      end
    RUBY
    assert_equal ['Foo', 'Bar', 'Baz'], @top_level.classes.map(&:full_name)
    foo, bar, baz = @top_level.classes
    assert_equal foo, bar.superclass
    assert_equal 'Object', baz.superclass unless accept_legacy_bug?
  end

  def test_class_new_notnew
    util_parser <<~RUBY
      class A
        def initialize(*args); end
      end

      class B
        ##
        # :args: a, b, c
        def initialize(*args); end
      end

      class C
        def self.initialize(*args); end
      end

      class D
        ##
        # :args: a, b, c
        def initialize(*args); end # :notnew:
      end

      class E
        def initialize(*args); end # :not-new:
      end

      class F
        def initialize(*args); end # :not_new:
      end

      class G
        def initialize(*args)
        end # :notnew:
      end
    RUBY

    expected = [
      'new(*args)', 'new(a, b, c)',
      'initialize(*args)', 'initialize(a, b, c)',
      'initialize(*args)', 'initialize(*args)',
      'initialize(*args)'
    ]
    arglists = @top_level.classes.map { |c| c.method_list.first.arglists }
    assert_equal expected, arglists
  end

  def test_class_mistaken_for_module
    util_parser <<~RUBY
      class A::Foo; end
      class B::Foo; end
      module C::Bar; end
      module D::Baz; end
      class A; end
      class X < C; end
    RUBY
    assert_equal ['A', 'C', 'X'], @top_level.classes.map(&:full_name)
    assert_equal ['B', 'D'], @top_level.modules.map(&:full_name)
  end

  def test_parenthesized_cdecl
    util_parser <<~RUBY
      module DidYouMean
        # Not a module, but creates a dummy module for document
        class << (NameErrorCheckers = Object.new)
          def new; end
        end
      end
    RUBY

    mod = @store.find_class_or_module('DidYouMean').modules.first
    assert_equal 'DidYouMean::NameErrorCheckers', mod.full_name
    assert_equal ['DidYouMean::NameErrorCheckers::new'], mod.method_list.map(&:full_name)
  end


  def test_ghost_method
    util_parser <<~RUBY
      class Foo
        ##
        # :method: one
        #
        # my method one

        ##
        # :method:
        # :call-seq:
        #   two(name)
        #
        # my method two

        ##
        # :method: three
        # :args: a, b
        #
        # my method three

        # :stopdoc:

        ##
        # :method: hidden1
        #
        # comment

        ##
        # :method:
        # :call-seq:
        #   hidden2(name)
        #
        # comment
      end
    RUBY

    klass = @store.find_class_named 'Foo'
    assert_equal 3, klass.method_list.size
    one, two, three = klass.method_list
    assert_equal 'Foo#one', one.full_name
    assert_equal 'Foo#two', two.full_name
    assert_equal 'Foo#three', three.full_name
    assert_equal 'two(name)', two.call_seq.chomp
    assert_equal 'three(a, b)', three.arglists
    assert_equal 'my method one', one.comment.text.strip
    assert_equal 'my method two', two.comment.text.strip
    assert_equal 'my method three', three.comment.text.strip
    assert_equal 3, one.line
    assert_equal 8, two.line
    assert_equal 15, three.line
    assert_equal @top_level, one.file
    assert_equal @top_level, two.file
    assert_equal @top_level, three.file
  end

  def test_invalid_meta_method
    util_parser <<~RUBY
      class Foo
        # These are invalid meta method comments
        # because meta method comment should start with `##`
        # but rdoc accepts them as meta method comments for now.

        # :method: m1

        # :singleton-method: sm1

        # :attr: a1

        # :attr_reader: ar1

        # :attr_writer: aw1

        # :attr_accessor: arw1

        # If there is a node following meta-like normal comment, it is not a meta method comment

        # :method: m2
        add_my_method(name)

        # :singleton-method: sm2
        add_my_singleton_method(name)

        # :method:
        add_my_method(:m3)

        # :singleton-method:
        add_my_singleton_method(:sm3)

        # :attr:
        add_my_attribute(:a2)

        # :attr-reader:
        add_my_attribute(:ar2)

        # :attr-writer:
        add_my_attribute(:aw2)

        # :attr-accessor:
        add_my_attribute(:arw2)

        # :attr: a3
        add_my_attribute_a3

        # :attr-reader: ar3
        add_my_attribute_ar3

        # :attr-writer: aw3
        add_my_attribute_aw2

        # :attr-accessor: arw3
        add_my_attribute_arw3
      end
    RUBY

    klass = @store.find_class_named 'Foo'
    assert_equal ['m1', 'sm1'], klass.method_list.map(&:name)
    assert_equal ['a1', 'ar1', 'aw1', 'arw1'], klass.attributes.map(&:name)
  end

  def test_unknown_meta_method
    util_parser <<~RUBY
      class Foo
        ##
        # :call-seq:
        #   two(name)
        #
        # method or singleton-method directive is missing
      end

      class Bar
        ##
        # unknown meta method
        add_my_method("foo" + "bar")
      end
    RUBY

    foo = @store.find_class_named 'Foo'
    bar = @store.find_class_named 'Bar'
    assert_equal [], foo.method_list.map(&:name)
    assert_equal ['unknown'], bar.method_list.map(&:name)
  end

  def test_method
    util_parser <<~RUBY
      class Foo
        # my method one
        def one; end
        # my method two
        def two(x); end
        # my method three
        def three x; end
      end
    RUBY

    klass = @store.find_class_named 'Foo'
    assert_equal 3, klass.method_list.size
    one, two, three = klass.method_list
    assert_equal 'Foo#one', one.full_name
    assert_equal 'Foo#two', two.full_name
    assert_equal 'Foo#three', three.full_name
    assert_equal 'one()', one.arglists
    assert_equal 'two(x)', two.arglists
    assert_equal 'three(x)', three.arglists unless accept_legacy_bug?
    assert_equal 'my method one', one.comment.text.strip
    assert_equal 'my method two', two.comment.text.strip
    assert_equal 'my method three', three.comment.text.strip
    assert_equal 3, one.line
    assert_equal 5, two.line
    assert_equal 7, three.line
    assert_equal @top_level, one.file
    assert_equal @top_level, two.file
    assert_equal @top_level, three.file
  end

  def test_method_toplevel
    util_parser <<~RUBY
      # comment
      def foo; end
    RUBY

    object = @store.find_class_named 'Object'
    foo = object.method_list.first
    assert_equal 'Object#foo', foo.full_name
    assert_equal 'comment', foo.comment.text.strip
    assert_equal @top_level, foo.file
  end

  def test_meta_method
    util_parser <<~RUBY
      class Foo
        ##
        # my method
        add_my_method :method_foo, :arg
      end
    RUBY

    klass = @store.find_class_named 'Foo'
    assert_equal 1, klass.method_list.size
    method = klass.method_list.first
    assert_equal 'Foo#method_foo', method.full_name
    assert_equal 'my method', method.comment.text.strip
    assert_equal 4, method.line
    assert_equal @top_level, method.file
  end

  def test_first_comment_is_not_a_meta_method
    util_parser <<~RUBY
      ##
      # first comment is not a meta method
      add_my_method :foo

      ##
      # this is a meta method
      add_my_method :bar
    RUBY

    object = @store.find_class_named 'Object'
    assert_equal ['bar'], object.method_list.map(&:name)
  end

  def test_meta_method_unknown
    util_parser <<~RUBY
      class Foo
        ##
        # my method
        add_my_method (:foo), :bar
      end
    RUBY

    klass = @store.find_class_named 'Foo'
    assert_equal 1, klass.method_list.size
    method = klass.method_list.first
    assert_equal 'Foo#unknown', method.full_name
    assert_equal 'my method', method.comment.text.strip
    assert_equal 4, method.line
    assert_equal @top_level, method.file
  end

  def test_meta_define_method
    util_parser <<~RUBY
      class Foo
        ##
        # comment 1
        define_method :foo do end
        ##
        # comment 2
        define_method :bar, ->{}
        # not a meta comment, not a meta method
        define_method :ignored do end
        class << self
          ##
          # comment 3
          define_method :baz do end
        end
      end
    RUBY

    klass = @store.find_class_named 'Foo'
    klass.method_list.last.singleton = true if accept_legacy_bug?
    assert_equal 3, klass.method_list.size
    assert_equal ['Foo#foo', 'Foo#bar', 'Foo::baz'], klass.method_list.map(&:full_name)
    assert_equal [false, false, true], klass.method_list.map(&:singleton)
    assert_equal ['comment 1', 'comment 2', 'comment 3'], klass.method_list.map { |m| m.comment.text.strip }
    assert_equal [4, 7, 13], klass.method_list.map(&:line)
    assert_equal [@top_level] * 3, klass.method_list.map(&:file)
  end

  def test_method_definition_nested_inside_block
    util_parser <<~RUBY
      module A
        extend ActiveSupport::Concern
        included do
          ##
          # :singleton-method:
          # comment foo
          mattr_accessor :foo

          ##
          # :method: bar
          # comment bar
          add_my_method :bar
        end

        tap do
          # comment baz1
          def baz1; end
        end

        self.tap do
          # comment baz2
          def baz2; end
        end

        my_decorator def self.baz3; end

        self.my_decorator def baz4; end
      end
    RUBY
    mod = @store.find_module_named 'A'
    methods = mod.method_list
    assert_equal ['A::foo', 'A#bar', 'A#baz1', 'A#baz2', 'A::baz3', 'A#baz4'], methods.map(&:full_name)
    assert_equal ['comment foo', 'comment bar', 'comment baz1', 'comment baz2'], methods.take(4).map { |m| m.comment.text.strip }
  end

  def test_method_yields_directive
    util_parser <<~RUBY
      class Foo
        def f1(a, &b); end

        def f2
          def o.foo
            yield :dummy
          end
          yield
        end

        def f3(&b)
          yield a, *b, c: 1
          yield 1, 2, 3
        end

        def f4(a, &b) # :yields: d, e
          yields 1, 2
        end

        def f5 # :yield: f
          yields 1, 2
        end

        def f6; end # :yields:

        ##
        # :yields: g, h
        add_my_method :f7
      end
    RUBY

    klass = @top_level.classes.first
    methods = klass.method_list
    expected = [
      'f1(a, &b)',
      'f2() { || ... }',
      'f3() { |a, *b, c: 1| ... }',
      'f4(a) { |d, e| ... }',
      'f5() { |f| ... }',
      'f6() { || ... }',
      'f7() { |g, h| ... }'
    ]
    assert_equal expected, methods.map(&:arglists)
  end

  def test_calls_super
    util_parser <<~RUBY
      class A
        def m1; foo; bar; end
        def m2; if cond; super(a); end; end # SuperNode
        def m3; tap do; super; end; end # ForwardingSuperNode
        def m4; def a.b; super; end; end # super inside another method
      end
    RUBY

    klass = @store.find_class_named 'A'
    methods = klass.method_list
    assert_equal ['m1', 'm2', 'm3', 'm4'], methods.map(&:name)
    assert_equal [false, true, true, false], methods.map(&:calls_super)
  end

  def test_method_args_directive
    util_parser <<~RUBY
      class Foo
        def method1 # :args: a, b, c
        end

        ##
        # :args: d, e, f
        def method2(*args); end

        ##
        # :args: g, h
        add_my_method :method3
      end
    RUBY

    klass = @top_level.classes.first
    methods = klass.method_list
    assert_equal ['method1(a, b, c)', 'method2(d, e, f)', 'method3(g, h)'], methods.map(&:arglists)
  end

  def test_class_repeatedly
    util_parser <<~RUBY
      class Foo
        def foo; end
      end
      class Foo
        def bar; end
      end
    RUBY
    util_parser <<~RUBY
      class Foo
        def baz; end
      end
    RUBY

    klass = @store.find_class_named 'Foo'
    assert_equal ['Foo#foo', 'Foo#bar', 'Foo#baz'], klass.method_list.map(&:full_name)
  end

  def test_undefined_singleton_class_defines_module
    util_parser <<~RUBY
      class << Foo
      end
      class << ::Bar
      end
    RUBY

    modules = @store.all_modules
    assert_equal ['Foo', 'Bar'], modules.map(&:name)
  end

  def test_singleton_class
    util_parser <<~RUBY
      class A; end
      class Foo
        def self.m1; end
        def (any expression).dummy1; end
        class << self
          def m2; end
          def self.dummy2; end
        end
        class << A
          def dummy3; end
        end
        class << Foo
          def m3; end
          def self.dummy4; end
        end
        class << ::Foo
          def m4; end
        end
        class << (any expression)
          def dummy5; end
        end
      end
      class << Foo
        def m5; end
      end
      class << ::Foo
        def m6; end
      end
    RUBY

    klass = @store.find_class_named 'Foo'
    methods = klass.method_list
    methods = methods.reject {|m| m.name =~ /dummy2|dummy4/ } if accept_legacy_bug?
    assert_equal ['m1', 'm2', 'm3', 'm4', 'm5', 'm6'], methods.map(&:name)
    assert_equal [true] * 6, methods.map(&:singleton)
  end

  def test_singleton_class_meta_method
    util_parser <<~RUBY
      class Foo
        ##
        # :singleton-method: m1

        ##
        # :singleton-method:
        add_my_smethod :m2, :arg

        ##
        # :singleton-method:
        add_my_smethod 'm3', :arg

        # comment
        class << self
          ##
          # method of a singleton class is a singleton method
          # :method: m4

          ##
          # :singleton-method: m5
        end
      end
    RUBY

    klass = @store.find_class_named 'Foo'
    assert_equal ['m1', 'm2', 'm3', 'm4', 'm5'], klass.method_list.map(&:name)
    klass.method_list[3].singleton = true if accept_legacy_bug?
    assert_equal [true] * 5, klass.method_list.map(&:singleton)
  end

  def test_method_nested_visibility
    util_parser <<~RUBY
      class A
        def pub1; end
        private
        def pri1; end
        class B
          def pub_b1; end
          private
          def pri_b1; end
          public
          def pub_b2; end
        end
        def pri2; end
      end
      class A
        def pub2; end
        private
        def pri2; end
      end
    RUBY
    klass_a = @store.find_class_named 'A'
    klass_b = klass_a.find_class_named 'B'
    public_a = klass_a.method_list.select { |m| m.visibility == :public }.map(&:name)
    public_b = klass_b.method_list.select { |m| m.visibility == :public }.map(&:name)
    assert_equal ['pub1', 'pub2'], public_a
    assert_equal ['pub_b1', 'pub_b2'], public_b
  end

  def test_attributes_visibility
    util_parser <<~RUBY
      class A
        attr :pub_a
        attr_reader :pub_r
        attr_writer :pub_w
        attr_accessor :pub_rw
        private
        attr :pri_a
        attr_reader :pri_r
        attr_writer :pri_w
        attr_accessor :pri_rw
      end
    RUBY
    klass = @store.find_class_named 'A'
    assert_equal ['pub_a', 'pub_r', 'pub_w', 'pub_rw', 'pri_a', 'pri_r', 'pri_w', 'pri_rw'], klass.attributes.map(&:name)
    assert_equal [:public] * 4 + [:private] * 4, klass.attributes.map(&:visibility)
  end

  def test_method_singleton_class_visibility
    util_parser <<~RUBY
      class A
        def self.pub1; end
        private
        def self.pub2; end
        class << self
          def pub3; end
          private
          def pri1; end
          public
          def pub4; end
          private
        end
      end
    RUBY
    klass = @store.find_class_named 'A'
    public_singleton_methods = klass.method_list.select { |m| m.singleton && m.visibility == :public }
    assert_equal ['pub1', 'pub2', 'pub3', 'pub4'], public_singleton_methods.map(&:name)
  end

  def test_private_def_public_def
    util_parser <<~RUBY
      class A
        private def m1; end
        public def m2; end
        private
        public def m3; end
      end
    RUBY
    klass = @store.find_class_named 'A'
    public_methods = klass.method_list.select { |m| m.visibility == :public }
    assert_equal ['m2', 'm3'], public_methods.map(&:name)
  end

  def test_define_method_visibility
    util_parser <<~RUBY
      class A
        private
        ##
        # my private method
        define_method :m1 do end
        public
        ##
        # my public method
        define_method :m2 do end
      end
    RUBY
    klass = @store.find_class_named 'A'
    methods = klass.method_list
    assert_equal ['m1', 'm2'], methods.map(&:name)
    assert_equal [:private, :public], methods.map(&:visibility)
  end

  def test_module_function
    util_parser <<~RUBY
      class A
        def m1; end
        def m2; end
        def m3; end
        module_function :m1, :m3
        module_function def m4; end
      end
    RUBY
    klass = @store.find_class_named 'A'
    instance_methods = klass.method_list.reject(&:singleton)
    singleton_methods = klass.method_list.select(&:singleton)
    if accept_legacy_bug?
      instance_methods.last.visibility = :private
      singleton_methods << singleton_methods.last.dup
      singleton_methods.last.name = 'm4'
    end
    assert_equal ['m1', 'm2', 'm3', 'm4'], instance_methods.map(&:name)
    assert_equal [:private, :public, :private, :private], instance_methods.map(&:visibility)
    assert_equal ['m1', 'm3', 'm4'], singleton_methods.map(&:name)
    assert_equal [:public, :public, :public], singleton_methods.map(&:visibility)
  end

  def test_class_method_visibility
    util_parser <<~RUBY
      class A
        def self.m1; end
        def self.m2; end
        def self.m3; end
        private_class_method :m1, :m2
        public_class_method :m1, :m3
        private_class_method def self.m4; end
        public_class_method def self.m5; end
      end
    RUBY
    klass = @store.find_class_named 'A'
    public_methods = klass.method_list.select { |m| m.visibility == :public }
    assert_equal ['m1', 'm3', 'm5'], public_methods.map(&:name) unless accept_legacy_bug?
  end

  def test_method_change_visibility
    util_parser <<~RUBY
      class A
        def m1; end
        def m2; end
        def m3; end
        def m4; end
        def m5; end
        private :m2, :m3, :m4
        public :m1, :m3
      end
      class << A
        def m1; end
        def m2; end
        def m3; end
        def m4; end
        def m5; end
        private :m1, :m2, :m3
        public :m2, :m4
      end
    RUBY
    klass = @store.find_class_named 'A'
    public_methods = klass.method_list.select { |m| !m.singleton && m.visibility == :public }
    public_singleton_methods = klass.method_list.select { |m| m.singleton && m.visibility == :public }
    assert_equal ['m1', 'm3', 'm5'], public_methods.map(&:name)
    assert_equal ['m2', 'm4', 'm5'], public_singleton_methods.map(&:name)
  end

  def test_undocumentable_change_visibility
    pend if accept_legacy_bug?
    util_parser <<~RUBY
      class A
        def m1; end
        def self.m2; end
        private 42, :m # maybe not Module#private
        # ignore all non-standard `private def` and `private_class_method def`
        private def self.m1; end
        private_class_method def m2; end
        private def to_s.m1; end
        private_class_method def to_s.m2; end
      end
    RUBY
    klass = @store.find_class_named 'A'
    assert_equal [:public] * 4, klass.method_list.map(&:visibility)
  end

  def test_method_visibility_change_in_subclass
    pend 'not implemented' if accept_legacy_bug?
    util_parser <<~RUBY
      class A
        def m1; end
        def m2; end
        private :m2
      end
      class B < A
        private :m1
        public :m2
      end
    RUBY

    superclass = @store.find_class_named('A')
    klass = @store.find_class_named('B')
    assert_equal ['m1', 'm2'], superclass.method_list.map(&:name)
    assert_equal ['m1', 'm2'], klass.method_list.map(&:name)
    assert_equal [:public, :private], superclass.method_list.map(&:visibility)
    assert_equal [:private, :public], klass.method_list.map(&:visibility)
  end

  def test_singleton_method_visibility_change_in_subclass
    util_parser <<~RUBY
      class A
        def self.m1; end
        def self.m2; end
        private_class_method :m2
      end
      class B < A
        private_class_method :m1
        public_class_method :m2
      end
    RUBY

    superclass = @store.find_class_named('A')
    klass = @store.find_class_named('B')
    assert_equal ['m1', 'm2'], superclass.method_list.map(&:name)
    assert_equal ['m1', 'm2'], klass.method_list.map(&:name)
    assert_equal [:public, :private], superclass.method_list.map(&:visibility)
    assert_equal [:private, :public], klass.method_list.map(&:visibility)
  end

  def test_alias
    util_parser <<~RUBY
      class Foo
        def bar; end
        def bar2; alias :dummy :bar; end
        # comment
        alias :baz1 :bar # :nodoc:
        alias :baz2 :bar
        # :stopdoc:
        alias :baz3 :bar
      end
    RUBY
    klass = @store.find_class_named 'Foo'
    assert_equal ['Foo#bar', 'Foo#bar2', 'Foo#baz2'], klass.method_list.map(&:full_name)
    m = klass.method_list.last
    assert_equal 'Foo#bar', m.is_alias_for.full_name
    assert_equal 'Foo#baz2', m.full_name
    assert_equal klass, m.parent
  end

  def test_alias_singleton
    util_parser <<~RUBY
      class Foo
        class << self
          def bar; end
          # comment
          alias :baz :bar
          # :stopdoc:
          alias :baz2 :bar
        end
      end
    RUBY
    klass = @store.find_class_named 'Foo'
    m = klass.class_method_list.last
    assert_equal 'Foo::bar', m.is_alias_for.full_name
    assert_equal 'Foo::baz', m.full_name
    assert_equal 'comment', m.comment.text
    assert_equal klass, m.parent
  end

  def test_alias_method
    util_parser <<~RUBY
      class Foo
        def foo; end
        private
        alias_method :foo2, :foo
        def bar; end
        public
        alias_method :bar2, :bar
        private :foo
        public :bar
      end
    RUBY
    foo, foo2, bar, bar2 = @top_level.classes.first.method_list
    assert_equal 'foo', foo.name
    assert_equal 'bar', bar.name
    assert_equal 'foo2', foo2.name
    assert_equal 'bar2', bar2.name
    assert_equal 'foo', foo2.is_alias_for.name
    assert_equal 'bar', bar2.is_alias_for.name
    unless accept_legacy_bug?
      assert_equal :private, foo.visibility
      assert_equal :public, foo2.visibility
      assert_equal :public, bar.visibility
      assert_equal :private, bar2.visibility
    end
  end

  def test_invalid_alias_method
    pend if accept_legacy_bug?
    util_parser <<~RUBY
      class Foo
        def foo; end
        alias_method
        alias_method :foo
        alias_method :foo, :bar, :baz
        alias_method 42, :foo
      end
    RUBY
    assert_equal ['foo'], @top_level.classes.first.method_list.map(&:name)
  end

  def test_alias_method_stopdoc_nodoc
    util_parser <<~RUBY
      class Foo
        def foo; end
        # :stopdoc:
        alias_method :foo2, :foo
        # :startdoc:
        alias_method :foo3, :foo # :nodoc:
        alias_method :foo4, :foo
      end
    RUBY
    assert_equal ['foo', 'foo4'], @top_level.classes.first.method_list.map(&:name)
  end

  def test_attributes
    util_parser <<~RUBY
      class Foo
        # attrs
        attr :attr1, :attr2
        # readers
        attr_reader :reader1, :reader2
        # writers
        attr_writer :writer1, :writer2
        # accessors
        attr_accessor :accessor1, :accessor2
        # :stopdoc:
        attr :attr3, :attr4
        attr_reader :reader3, :reader4
        attr_writer :write3, :writer4
        attr_accessor :accessor3, :accessor4
      end
    RUBY
    klass = @store.find_class_named 'Foo'
    if accept_legacy_bug?
      a, r1, r2, w1, w2, rw1, rw2 = klass.attributes
      a1 = a.dup
      a2 = a.dup
      a1.rw = a2.rw = 'R'
      a2.name = 'attr2'
    else
      assert_equal 8, klass.attributes.size
      a1, a2, r1, r2, w1, w2, rw1, rw2 = klass.attributes
    end
    assert_equal ['attr1', 'attr2'], [a1.name, a2.name]
    assert_equal ['reader1', 'reader2'], [r1.name, r2.name]
    assert_equal ['writer1', 'writer2'], [w1.name, w2.name]
    assert_equal ['accessor1', 'accessor2'], [rw1.name, rw2.name]
    assert_equal ['R', 'R'], [a1.rw, a2.rw]
    assert_equal ['R', 'R'], [r1.rw, r2.rw]
    assert_equal ['W', 'W'], [w1.rw, w2.rw]
    assert_equal ['RW', 'RW'], [rw1.rw, rw2.rw]
    assert_equal ['attrs', 'attrs'], [a1.comment.text, a2.comment.text]
    assert_equal ['readers', 'readers'], [r1.comment.text, r2.comment.text]
    assert_equal ['writers', 'writers'], [w1.comment.text, w2.comment.text]
    assert_equal ['accessors', 'accessors'], [rw1.comment.text, rw2.comment.text]
    assert_equal [3, 3], [a1.line, a2.line]
    assert_equal [5, 5], [r1.line, r2.line]
    assert_equal [7, 7], [w1.line, w2.line]
    assert_equal [9, 9], [rw1.line, rw2.line]
    assert_equal [@top_level] * 8, [a1, a2, r1, r2, w1, w2, rw1, rw2].map(&:file)
  end

  def test_undocumentable_attributes
    util_parser <<~RUBY
      class Foo
        attr
        attr 42, :foo
      end
    RUBY
    klass = @store.find_class_named 'Foo'
    assert_empty klass.method_list
    assert_empty klass.attributes
  end

  def test_singleton_class_attributes
    util_parser <<~RUBY
      class Foo
        class << self
          attr :a
          attr_reader :r
          attr_writer :w
          attr_accessor :rw
        end
      end
    RUBY
    klass = @store.find_class_named 'Foo'
    attributes = klass.attributes
    assert_equal ['a', 'r', 'w', 'rw'], attributes.map(&:name)
    assert_equal [true] * 4, attributes.map(&:singleton)
  end

  def test_attributes_nodoc
    util_parser <<~RUBY
      class Foo
        attr :attr1, :attr2 # :nodoc:
        attr :attr3
        attr_reader :reader1, :reader2 # :nodoc:
        attr_reader :reader3
        attr_writer :writer1, :writer2 # :nodoc:
        attr_writer :writer3
        attr_accessor :accessor1, :accessor2 # :nodoc:
        attr_accessor :accessor3
      end
    RUBY
    klass = @store.find_class_named 'Foo'
    unless accept_legacy_bug?
      assert_equal 4, klass.attributes.size
    end
  end

  def test_attributes_nodoc_track
    @options.visibility = :nodoc
    util_parser <<~RUBY
      class Foo
        attr :attr1, :attr2 # :nodoc:
        attr :attr3
        attr_reader :reader1, :reader2 # :nodoc:
        attr_reader :reader3
        attr_writer :writer1, :writer2 # :nodoc:
        attr_writer :writer3
        attr_accessor :accessor1, :accessor2 # :nodoc:
        attr_accessor :accessor3
      end
    RUBY
    klass = @store.find_class_named 'Foo'
    unless accept_legacy_bug?
      assert_equal 12, klass.attributes.size
    end
  end

  def test_method_nodoc_stopdoc
    util_parser <<~RUBY
      class Foo
        def doc1; end
        def nodoc1; end # :nodoc:
        def doc2; end
        def nodoc2 # :nodoc:
        end
        def doc3; end
        def nodoc3
        end # :nodoc:
        def doc4; end
        # :stopdoc:
        def nodoc4; end
      end
    RUBY
    klass = @store.find_class_named 'Foo'
    assert_equal ['doc1', 'doc2', 'doc3', 'doc4'], klass.method_list.map(&:name)
  end

  def test_method_nodoc_track
    @options.visibility = :nodoc
    util_parser <<~RUBY
      class Foo
        def doc1; end
        def nodoc1; end # :nodoc:
        def doc2; end
        def nodoc2 # :nodoc:
        end
        def doc3; end
        def nodoc3
        end # :nodoc:
        def doc4; end
      end
    RUBY
    klass = @store.find_class_named 'Foo'
    assert_equal ['doc1', 'nodoc1', 'doc2', 'nodoc2', 'doc3', 'nodoc3', 'doc4'], klass.method_list.map(&:name)
    assert_equal [true, nil, true, nil, true, nil, true], klass.method_list.map(&:document_self)
  end

  def test_meta_attributes
    util_parser <<~RUBY
      class Foo
        ##
        # :attr:
        # attrs
        add_my_method :attr1, :attr2
        ##
        # :attr_reader:
        # readers
        add_my_method :reader1, :reader2
        ##
        # :attr_writer:
        # writers
        add_my_method :writer1, :writer2
        ##
        # :attr_accessor:
        # accessors
        add_my_method :accessor1, :accessor2

        # :stopdoc:

        ##
        # :attr:
        add_my_method :attr3
        ##
        # :attr_reader:
        add_my_method :reader3
        ##
        # :attr_writer:
        add_my_method :writer3
        ##
        # :attr_accessor:
        add_my_method :accessor3
      end
    RUBY
    klass = @store.find_class_named 'Foo'
    assert_equal 8, klass.attributes.size
    a1, a2, r1, r2, w1, w2, rw1, rw2 = klass.attributes
    assert_equal ['attr1', 'attr2'], [a1.name, a2.name]
    assert_equal ['reader1', 'reader2'], [r1.name, r2.name]
    assert_equal ['writer1', 'writer2'], [w1.name, w2.name]
    assert_equal ['accessor1', 'accessor2'], [rw1.name, rw2.name]
    a1.rw = a2.rw = 'R' if accept_legacy_bug?
    assert_equal ['R', 'R'], [a1.rw, a2.rw]
    assert_equal ['R', 'R'], [r1.rw, r2.rw]
    assert_equal ['W', 'W'], [w1.rw, w2.rw]
    assert_equal ['RW', 'RW'], [rw1.rw, rw2.rw]
    assert_equal ['attrs', 'attrs'], [a1.comment.text, a2.comment.text]
    assert_equal ['readers', 'readers'], [r1.comment.text, r2.comment.text]
    assert_equal ['writers', 'writers'], [w1.comment.text, w2.comment.text]
    assert_equal ['accessors', 'accessors'], [rw1.comment.text, rw2.comment.text]
    assert_equal [@top_level] * 8, [a1, a2, r1, r2, w1, w2, rw1, rw2].map(&:file)
  end

  def test_meta_attributes_named
    util_parser <<~RUBY
      class Foo
        ##
        # comment a
        # :attr: attr1
        add_my_method :a1
        ##
        # comment r
        # :attr_reader: reader1
        add_my_method :r1
        ##
        # comment w
        # :attr_writer: writer1
        add_my_method :w1
        ##
        # comment rw
        # :attr_accessor: accessor1
        add_my_method :rw1

        # :stopdoc:

        ##
        # :attr: attr2
        add_my_method :a2
        ##
        # :attr_reader: reader2
        add_my_method :r2
        ##
        # :attr_writer: writer2
        add_my_method :w2
        ##
        # :attr_accessor: accessor2
        add_my_method :rw2
      end
    RUBY
    klass = @store.find_class_named 'Foo'
    assert_equal 4, klass.attributes.size
    a, r, w, rw = klass.attributes
    assert_equal 'attr1', a.name
    assert_equal 'reader1', r.name
    assert_equal 'writer1', w.name
    assert_equal 'accessor1', rw.name
    a.rw = 'R' if accept_legacy_bug?
    assert_equal 'R', a.rw
    assert_equal 'R', r.rw
    assert_equal 'W', w.rw
    assert_equal 'RW', rw.rw
    assert_equal 'comment a', a.comment.text
    assert_equal 'comment r', r.comment.text
    assert_equal 'comment w', w.comment.text
    assert_equal 'comment rw', rw.comment.text
    assert_equal [@top_level] * 4, [a, r, w, rw].map(&:file)
  end

  def test_constant
    util_parser <<~RUBY
      class Foo
        A = (any expression 1)
        def f
          DUMMY1 = (any expression 2)
        end
        class Bar; end
        Bar::B = (any expression 3)
        ::C = (any expression 4)
        # :stopdoc:
        DUMMY2 = 1
        # :startdoc:
        D = (any expression 5)
        E = (any expression 6) # :nodoc:
        F = (
          any expression 7
        ) # :nodoc:
      end
      G = (any expression 8)
    RUBY
    foo = @top_level.classes.first
    bar = foo.classes.first
    object = @top_level.find_class_or_module('Object')
    assert_equal ['A', 'D', 'E', 'F'], foo.constants.map(&:name) unless accept_legacy_bug?
    assert_equal '(any expression 1)', foo.constants.first.value
    assert_equal ['B'], bar.constants.map(&:name)
    assert_equal ['C', 'G'], object.constants.map(&:name) unless accept_legacy_bug?
    all_constants = foo.constants + bar.constants + object.constants
    assert_equal [@top_level] * 7, all_constants.map(&:file) unless accept_legacy_bug?
    assert_equal [2, 12, 13, 14, 7, 8, 18], all_constants.map(&:line) unless accept_legacy_bug?
  end

  def test_nodoc_constant_assigned_without_nodoc_comment
    util_parser <<~RUBY
      module Foo
        A = 1
        B = 1 # :nodoc:
        begin
          C = 1 # :nodoc:
        rescue
          C = 2
        end
      end
      Foo::B = 2
      Foo::D = 2
    RUBY
    mod = @top_level.modules.first
    assert_equal ['A', 'B', 'C', 'D'], mod.constants.map(&:name)
    assert_equal [false, true, true, false], mod.constants.map(&:received_nodoc)
  end

  def test_constant_visibility
    util_parser <<~RUBY
      class C
        A = 1
        B = 2
        C = 3
        private_constant
        private_constant foo
        private_constant :A
        private_constant :B, :C
        public_constant :B
      end
    RUBY
    klass = @store.find_class_named 'C'
    const_a, const_b, const_c = klass.constants.sort_by(&:name)

    assert_equal 'A', const_a.name
    assert_equal :private, const_a.visibility

    assert_equal 'B', const_b.name
    assert_equal :public, const_b.visibility

    assert_equal 'C', const_c.name
    assert_equal :private, const_c.visibility
  end

  def test_constant_assignment_to_undefined_module_path
    util_parser <<~RUBY
      A::B::C = 1
    RUBY
    a = @top_level.find_module_named 'A'
    b = a.find_module_named 'B'
    c = b.constants.first
    assert_equal 'A::B::C', c.full_name
  end

  def test_constant_alias
    util_parser <<~RUBY
      class Foo
        class Bar; end
        A = Bar
        # B = ::Foo # master branch has bug
        C = Foo::Bar
      end
    RUBY
    klass = @top_level.classes.first
    assert_equal [], klass.modules.map(&:full_name)
    assert_equal ['Foo::Bar', 'Foo::A', 'Foo::C'], klass.classes.map(&:full_name)
    assert_equal ['Foo::A', 'Foo::C'], klass.constants.map(&:full_name)
    assert_equal 'Foo::A', klass.find_module_named('A').full_name
    assert_equal 'Foo::C', klass.find_module_named('C').full_name
  end

  def test_constant_method
    util_parser <<~RUBY
      def Object.foo; end
      class A
        class B
          class C
            def B.bar; end
          end
        end
      end
      def UNKNOWN.baz; end
    RUBY

    object = @store.find_class_named 'Object'
    klass = @store.find_class_named 'A::B'
    unknown = @store.find_module_named('UNKNOWN')
    assert_equal 'Object::foo', object.method_list.first.full_name
    assert_equal 'A::B::bar', klass.method_list.first.full_name
    assert_equal 'UNKNOWN::baz', unknown.method_list.first.full_name
  end

  def test_true_false_nil_method
    util_parser <<~RUBY
      def nil.foo; end
      def true.bar; end
      def false.baz; end
    RUBY
    sep = accept_legacy_bug? ? '::' : '#'
    assert_equal "NilClass#{sep}foo", @store.find_class_named('NilClass').method_list.first.full_name
    assert_equal "TrueClass#{sep}bar", @store.find_class_named('TrueClass').method_list.first.full_name
    assert_equal "FalseClass#{sep}baz", @store.find_class_named('FalseClass').method_list.first.full_name
  end

  def test_include_extend
    util_parser <<~RUBY
      module I; end
      module E; end
      class C
        # my include
        include I
        # my extend
        extend E
      end
      module M
        include I
        extend E
      end
    RUBY
    klass = @store.find_class_named 'C'
    mod = @store.find_module_named 'M'
    assert_equal ['I'], klass.includes.map(&:name)
    assert_equal ['E'], klass.extends.map(&:name)
    assert_equal ['I'], mod.includes.map(&:name)
    assert_equal ['E'], mod.extends.map(&:name)
    assert_equal 'my include', klass.includes.first.comment.text.strip
    assert_equal 'my extend', klass.extends.first.comment.text.strip
  end

  def test_include_extend_to_singleton_class
    pend 'not implemented' if accept_legacy_bug?
    util_parser <<~RUBY
      class Foo
        class << self
          # include to singleton class is extend
          include I
          # extend to singleton class is not documentable
          extend E
        end
      end
    RUBY

    klass = @top_level.classes.first
    assert_equal [], klass.includes.map(&:name)
    assert_equal ['I'], klass.extends.map(&:name)
  end

  def test_include_with_module_nesting
    util_parser <<~RUBY
      module A
        module M; end
        module B
          module M; end
          module C
            module M; end
            module D
              module M; end
            end
          end
        end
      end

      module A::B
        class C::D::Foo
          include M
        end
      end
      # TODO: make test pass with the following code appended
      # module A::B::C
      #   class D::Foo
      #     include M
      #   end
      # end
    RUBY
    klass = @store.find_class_named 'A::B::C::D::Foo'
    assert_equal 'A::B::M', klass.includes.first.module.full_name
  end

  def test_various_argument_include
    pend 'not implemented' if accept_legacy_bug?
    util_parser <<~RUBY
      module A; end
      module B; end
      module C; end
      class A
        include
        include A, B
        include 42, C # Maybe not Module#include
      end
    RUBY
    klass = @top_level.classes.first
    assert_equal ['A', 'B'], klass.includes.map(&:name)
  end

  def test_require
    util_parser <<~RUBY
      require
      require 'foo/bar'
      require_relative 'is/not/supported/yet'
      require "\#{embed}"
      require (any expression)
    RUBY
    assert_equal ['foo/bar'], @top_level.requires.map(&:name)
  end

  def test_statements_identifier_alias_method_before_original_method
    # This is not strictly legal Ruby code, but it simulates finding an alias
    # for a method before finding the original method, which might happen
    # to rdoc if the alias is in a different file than the original method
    # and rdoc processes the alias' file first.
    util_parser <<~RUBY
      class Foo
        alias_method :foo2, :foo
        alias_method :foo3, :foo
      end

      class Foo
        def foo(); end
        alias_method :foo4, :foo
        alias_method :foo5, :unknown
      end
    RUBY

    foo = @top_level.classes.first.method_list[0]
    assert_equal 'foo', foo.name

    foo2 = @top_level.classes.first.method_list[1]
    assert_equal 'foo2', foo2.name
    assert_equal 'foo', foo2.is_alias_for.name

    foo3 = @top_level.classes.first.method_list[2]
    assert_equal 'foo3', foo3.name
    assert_equal 'foo', foo3.is_alias_for.name

    foo4 = @top_level.classes.first.method_list.last
    assert_equal 'foo4', foo4.name
    assert_equal 'foo', foo4.is_alias_for.name

    assert_equal 'unknown', @top_level.classes.first.external_aliases[0].old_name
  end

  def test_class_definition_encountered_after_class_reference
    # The code below is not legal Ruby (Foo must have been defined before
    # Foo.bar is encountered), but RDoc might encounter Foo.bar before Foo if
    # they live in different files.

    util_parser <<-RUBY
      def Foo.bar
      end

      class Foo < IO
      end
    RUBY

    assert_empty @store.modules_hash
    assert_empty @store.all_modules

    klass = @top_level.classes.first
    assert_equal 'Foo', klass.full_name
    assert_equal 'IO', klass.superclass

    assert_equal 'bar', klass.method_list.first.name
  end

  def test_scan_duplicate_module
    util_parser <<~RUBY
      # comment a
      module Foo
      end

      # comment b
      module Foo
      end
    RUBY

    mod = @top_level.modules.first

    expected = [
      RDoc::Comment.new('comment a', @top_level),
      RDoc::Comment.new('comment b', @top_level)
    ]

    assert_equal expected, mod.comment_location.map { |c, _l| c }
  end

  def test_enddoc
    util_parser <<~RUBY
      class A
        class B; end
        # :enddoc:
        # :startdoc:
        class C; end
      end
      class D; end
      # :enddoc:
      # :startdoc:
      class E; end
    RUBY

    assert_equal ['A', 'A::B', 'D'], @store.all_classes.reject(&:ignored?).map(&:full_name)
  end

  def test_top_level_enddoc
    util_parser <<~RUBY
      class A; end
      # :enddoc:
      class B; end
      # :startdoc:
      class C; end
    RUBY

    assert_equal ['A'], @top_level.classes.reject(&:ignored?).map(&:name)
  end

  def test_section
    util_parser <<~RUBY
      class Foo
        # :section: section1
        attr :a1
        def m1; end
        # :section:
        def m2; end
        attr :a2
        # :section: section2
        def m3; end
        attr :a3
        module Bar
          def m4; end
          attr :a4
          # :section: section3
          def m5; end
          attr :a5
        end
        attr :a6
        def m6; end
      end
    RUBY
    foo = @top_level.classes.first
    bar = foo.modules.first
    assert_equal ['section1', nil, 'section2', 'section2'], foo.attributes.map { |m| m.section.title }
    assert_equal ['section1', nil, 'section2', 'section2'], foo.method_list.map { |m| m.section.title }
    assert_equal [nil, 'section3'], bar.attributes.map { |m| m.section.title }
    assert_equal [nil, 'section3'], bar.method_list.map { |m| m.section.title }
  end

  def test_category
    util_parser <<~RUBY
      class A
        # :category: cat1

        # comment
        attr :a1
        attr :a2
        def m1; end
        # :category: cat2

        # comment
        def m2; end
        def m3; end
        attr :a3

        # :category:
        attr :a4
        # :category:
        def m4; end

        ##
        # :category: cat3
        def m5; end

        ##
        # :category: cat4
        # :method: m6
      end
    RUBY
    klass = @top_level.classes.first
    assert_equal ['cat1', nil, nil, nil], klass.attributes.map { |m| m.section.title }
    assert_equal [nil, 'cat2', nil, nil, 'cat3', 'cat4'], klass.method_list.map { |m| m.section.title }
  end

  def test_ignore_constant_assign_rhs
    # Struct is not supported yet. Right hand side of constant assignment should be ignored.
    util_parser <<~RUBY
      module Foo
        def a; end
        Bar = Struct.new do
          def b; end
          ##
          # :method: c
        end
        Bar::Baz = Struct.new do
          def d; end
          ##
          # :method: e
        end
        ##
        # :method: f
      end
    RUBY
    mod = @top_level.modules.first
    assert_equal ['a', 'f'], mod.method_list.map(&:name)
  end

  def test_multibyte_method_name
    content = <<~RUBY
      class Foo
        # comment ω
        def ω() end
      end
    RUBY
    util_parser content
    assert_equal Encoding::UTF_8, content.encoding
    method = @top_level.classes.first.method_list.first
    assert_equal 'comment ω', method.comment.text.strip
    assert_equal 'ω', method.name
  end

  def test_options_encoding
    @options.encoding = Encoding::CP852
    util_parser <<~RUBY
      class Foo
        ##
        # this is my method
        add_my_method :foo
      end
    RUBY
    foo = @top_level.classes.first.method_list.first
    assert_equal 'foo', foo.name
    assert_equal 'this is my method', foo.comment.text
    assert_equal Encoding::CP852, foo.comment.text.encoding
  end

  def test_read_directive_linear_performance
    assert_linear_performance((1..5).map{|i|10**i}) do |i|
      util_parser '# ' + '0'*i + '=000:' + "\n def f; end"
    end
  end


  def test_markup_first_comment
    util_parser <<~RUBY
      # :markup: rd

      # ((*awesome*))
      class C
        # ((*radical*))
        def m
        end
      end
    RUBY

    c = @top_level.classes.first
    assert_equal 'rd', c.comment.format
    assert_equal 'rd', c.method_list.first.comment.format
  end

  def test_markup_override
    util_parser <<~RUBY
      # *awesome*
      class C
        # :markup: rd
        # ((*radical*))
        def m1; end

        # *awesome*
        def m2; end
      end
    RUBY

    c = @top_level.classes.first

    assert_equal 'rdoc', c.comment.format

    assert_equal ['rd', 'rdoc'], c.method_list.map { |m| m.comment.format }
  end

  def test_tomdoc_meta
    util_parser <<~RUBY
      # :markup: tomdoc

      class C

        # Signature
        #
        #   find_by_<field>[_and_<field>...](args)
        #
        # field - A field name.

      end
    RUBY

    c = @top_level.classes.first

    m = c.method_list.first

    assert_equal "find_by_<field>[_and_<field>...]", m.name
    assert_equal "find_by_<field>[_and_<field>...](args)\n", m.call_seq

    expected =
      doc(
        head(3, 'Signature'),
        list(:NOTE,
          item(%w[field],
            para('A field name.'))))
    expected.file = @top_level

    assert_equal expected, m.comment.parse
  end
end

class TestRDocParserPrismRuby < RDoc::TestCase
  include RDocParserPrismTestCases

  def accept_legacy_bug?
    false
  end

  def util_parser(content)
    @parser = RDoc::Parser::PrismRuby.new @top_level, @filename, content, @options, @stats
    @parser.scan
  end
end

# Run the same test with the original RDoc::Parser::Ruby
class TestRDocParserRubyWithPrismRubyTestCases < RDoc::TestCase
  include RDocParserPrismTestCases

  def accept_legacy_bug?
    true
  end

  def util_parser(content)
    @parser = RDoc::Parser::Ruby.new @top_level, @filename, content, @options, @stats
    @parser.scan
  end
end unless ENV['RDOC_USE_PRISM_PARSER']
