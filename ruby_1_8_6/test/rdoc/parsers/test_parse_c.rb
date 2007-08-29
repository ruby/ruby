require 'stringio'
require 'tempfile'
require 'test/unit'
require 'rdoc/parsers/parse_c'

class RDoc::C_Parser
  attr_accessor :classes

  public :do_classes, :do_constants
end

class TestRdocC_Parser < Test::Unit::TestCase

  def setup
    @tempfile = Tempfile.new self.class.name
    filename = @tempfile.path

    @top_level = RDoc::TopLevel.new filename
    @fn = filename
    @options = Options.instance
    @stats = RDoc::Stats.new

    @progress = StringIO.new
  end

  def teardown
    @tempfile.unlink
  end

  def test_do_classes_boot_class
    content = <<-EOF
/* Document-class: Foo
 * this is the Foo boot class
 */
VALUE cFoo = boot_defclass("Foo", 0);
    EOF

    klass = util_get_class content, 'cFoo'
    assert_equal "   this is the Foo boot class\n   ", klass.comment
  end

  def test_do_classes_class
    content = <<-EOF
/* Document-class: Foo
 * this is the Foo class
 */
VALUE cFoo = rb_define_class("Foo", rb_cObject);
    EOF

    klass = util_get_class content, 'cFoo'
    assert_equal "   this is the Foo class\n   ", klass.comment
  end

  def test_do_classes_class_under
    content = <<-EOF
/* Document-class: Kernel::Foo
 * this is the Foo class under Kernel
 */
VALUE cFoo = rb_define_class_under(rb_mKernel, "Foo", rb_cObject);
    EOF

    klass = util_get_class content, 'cFoo'
    assert_equal "   this is the Foo class under Kernel\n   ", klass.comment
  end

  def test_do_classes_module
    content = <<-EOF
/* Document-module: Foo
 * this is the Foo module
 */
VALUE mFoo = rb_define_module("Foo");
    EOF

    klass = util_get_class content, 'mFoo'
    assert_equal "   this is the Foo module\n   ", klass.comment
  end

  def test_do_classes_module_under
    content = <<-EOF
/* Document-module: Kernel::Foo
 * this is the Foo module under Kernel
 */
VALUE mFoo = rb_define_module_under(rb_mKernel, "Foo");
    EOF

    klass = util_get_class content, 'mFoo'
    assert_equal "   this is the Foo module under Kernel\n   ", klass.comment
  end

  def test_do_constants
    content = <<-EOF
#include <ruby.h>

void Init_foo(){
   VALUE cFoo = rb_define_class("Foo", rb_cObject);

   /* 300: The highest possible score in bowling */
   rb_define_const(cFoo, "PERFECT", INT2FIX(300));

   /* Huzzah!: What you cheer when you roll a perfect game */
   rb_define_const(cFoo, "CHEER", rb_str_new2("Huzzah!"));

   /* TEST\:TEST: Checking to see if escaped semicolon works */
   rb_define_const(cFoo, "TEST", rb_str_new2("TEST:TEST"));

   /* \\: The file separator on MS Windows */
   rb_define_const(cFoo, "MSEPARATOR", rb_str_new2("\\"));

   /* /: The file separator on Unix */
   rb_define_const(cFoo, "SEPARATOR", rb_str_new2("/"));

   /* C:\\Program Files\\Stuff: A directory on MS Windows */
   rb_define_const(cFoo, "STUFF", rb_str_new2("C:\\Program Files\\Stuff"));

   /* Default definition */
   rb_define_const(cFoo, "NOSEMI", INT2FIX(99));

   rb_define_const(cFoo, "NOCOMMENT", rb_str_new2("No comment"));

   /*
    * Multiline comment goes here because this comment spans multiple lines.
    * Multiline comment goes here because this comment spans multiple lines.
    */
   rb_define_const(cFoo, "MULTILINE", INT2FIX(1));

   /*
    * 1: Multiline comment goes here because this comment spans multiple lines.
    * Multiline comment goes here because this comment spans multiple lines.
    */
   rb_define_const(cFoo, "MULTILINE_VALUE", INT2FIX(1));

   /* Multiline comment goes here because this comment spans multiple lines.
    * Multiline comment goes here because this comment spans multiple lines.
    */
   rb_define_const(cFoo, "MULTILINE_NOT_EMPTY", INT2FIX(1));

}
    EOF

    parser = util_parser content

    parser.do_classes
    parser.do_constants

    klass = parser.classes['cFoo']
    assert klass

    constants = klass.constants
    assert !klass.constants.empty?

    constants = constants.map { |c| [c.name, c.value, c.comment] }

    assert_equal ['PERFECT', '300',
                  "\n      The highest possible score in bowling   \n   "],
                 constants.shift
    assert_equal ['CHEER', 'Huzzah!',
                  "\n      What you cheer when you roll a perfect game   \n   "],
                 constants.shift
    assert_equal ['TEST', 'TEST:TEST',
                  "\n      Checking to see if escaped semicolon works   \n   "],
                 constants.shift
    assert_equal ['MSEPARATOR', '\\',
                  "\n      The file separator on MS Windows   \n   "],
                 constants.shift
    assert_equal ['SEPARATOR', '/',
                  "\n      The file separator on Unix   \n   "],
                 constants.shift
    assert_equal ['STUFF', 'C:\\Program Files\\Stuff',
                  "\n      A directory on MS Windows   \n   "],
                 constants.shift
    assert_equal ['NOSEMI', 'INT2FIX(99)',
                  "\n      Default definition   \n   "],
                 constants.shift
    assert_equal ['NOCOMMENT', 'rb_str_new2("No comment")', nil],
                 constants.shift

    comment = <<-EOF.chomp

     
      Multiline comment goes here because this comment spans multiple lines.
      Multiline comment goes here because this comment spans multiple lines.
      
   
    EOF
    assert_equal ['MULTILINE', 'INT2FIX(1)', comment], constants.shift
    assert_equal ['MULTILINE_VALUE', '1', comment], constants.shift

    comment = <<-EOF.chomp

      Multiline comment goes here because this comment spans multiple lines.
      Multiline comment goes here because this comment spans multiple lines.
      
   
    EOF
    assert_equal ['MULTILINE_NOT_EMPTY', 'INT2FIX(1)', comment], constants.shift

    assert constants.empty?, constants.inspect
  end

  def test_find_class_comment_init
    content = <<-EOF
/*
 * a comment for class Foo
 */
void
Init_Foo(void) {
  VALUE foo = rb_define_class("Foo", rb_cObject);
}
    EOF

    klass = util_get_class content, 'foo'

    assert_equal "  \n   a comment for class Foo\n   \n", klass.comment
  end

  def test_find_class_comment_define_class
    content = <<-EOF
/*
 * a comment for class Foo
 */
VALUE foo = rb_define_class("Foo", rb_cObject);
    EOF

    klass = util_get_class content, 'foo'

    assert_equal "  \n   a comment for class Foo\n   ", klass.comment
  end

  def test_find_class_comment_define_class
    content = <<-EOF
/*
 * a comment for class Foo on Init
 */
void
Init_Foo(void) {
    /*
     * a comment for class Foo on rb_define_class
     */
    VALUE foo = rb_define_class("Foo", rb_cObject);
}
    EOF

    klass = util_get_class content, 'foo'

    assert_equal "  \n   a comment for class Foo on Init\n   \n", klass.comment
  end

  def util_get_class(content, name)
    parser = util_parser content
    parser.do_classes
    parser.classes[name]
  end

  def util_parser(content)
    parser = RDoc::C_Parser.new @top_level, @fn, content, @options, @stats
    parser.progress = @progress
    parser
  end

end

