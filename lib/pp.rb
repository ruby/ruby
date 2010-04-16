# == Pretty-printer for Ruby objects.
#
# = Which seems better?
#
# non-pretty-printed output by #p is:
#   #<PP:0x81fedf0 @genspace=#<Proc:0x81feda0>, @group_queue=#<PrettyPrint::GroupQueue:0x81fed3c @queue=[[#<PrettyPrint::Group:0x81fed78 @breakables=[], @depth=0, @break=false>], []]>, @buffer=[], @newline="\n", @group_stack=[#<PrettyPrint::Group:0x81fed78 @breakables=[], @depth=0, @break=false>], @buffer_width=0, @indent=0, @maxwidth=79, @output_width=2, @output=#<IO:0x8114ee4>>
#
# pretty-printed output by #pp is:
#   #<PP:0x81fedf0
#    @buffer=[],
#    @buffer_width=0,
#    @genspace=#<Proc:0x81feda0>,
#    @group_queue=
#     #<PrettyPrint::GroupQueue:0x81fed3c
#      @queue=
#       [[#<PrettyPrint::Group:0x81fed78 @break=false, @breakables=[], @depth=0>],
#        []]>,
#    @group_stack=
#     [#<PrettyPrint::Group:0x81fed78 @break=false, @breakables=[], @depth=0>],
#    @indent=0,
#    @maxwidth=79,
#    @newline="\n",
#    @output=#<IO:0x8114ee4>,
#    @output_width=2>
#
# I like the latter.  If you do too, this library is for you.
#
# = Usage
#
#   pp(obj)
#
# output +obj+ to +$>+ in pretty printed format.
#
# It returns +nil+.
#
# = Output Customization
# To define your customized pretty printing function for your classes,
# redefine a method #pretty_print(+pp+) in the class.
# It takes an argument +pp+ which is an instance of the class PP.
# The method should use PP#text, PP#breakable, PP#nest, PP#group and
# PP#pp to print the object.
#
# = Author
# Tanaka Akira <akr@m17n.org>

require 'prettyprint'

module Kernel
  # returns a pretty printed object as a string.
  def pretty_inspect
    PP.pp(self, '')
  end

  private
  # prints arguments in pretty form.
  #
  # pp returns nil.
  def pp(*objs) # :doc:
    objs.each {|obj|
      PP.pp(obj)
    }
    nil
  end
  module_function :pp
end

class PP < PrettyPrint
  # Outputs +obj+ to +out+ in pretty printed format of
  # +width+ columns in width.
  #
  # If +out+ is omitted, +$>+ is assumed.
  # If +width+ is omitted, 79 is assumed.
  #
  # PP.pp returns +out+.
  def PP.pp(obj, out=$>, width=79)
    q = PP.new(out, width)
    q.guard_inspect_key {q.pp obj}
    q.flush
    #$pp = q
    out << "\n"
  end

  # Outputs +obj+ to +out+ like PP.pp but with no indent and
  # newline.
  #
  # PP.singleline_pp returns +out+.
  def PP.singleline_pp(obj, out=$>)
    q = SingleLine.new(out)
    q.guard_inspect_key {q.pp obj}
    q.flush
    out
  end

  # :stopdoc:
  def PP.mcall(obj, mod, meth, *args, &block)
    mod.instance_method(meth).bind(obj).call(*args, &block)
  end
  # :startdoc:

  @sharing_detection = false
  class << self
    # Returns the sharing detection flag as a boolean value.
    # It is false by default.
    attr_accessor :sharing_detection
  end

  module PPMethods
    InspectKey = :__inspect_key__

    def guard_inspect_key
      if Thread.current[InspectKey] == nil
        Thread.current[InspectKey] = []
      end

      save = Thread.current[InspectKey]

      begin
        Thread.current[InspectKey] = []
        yield
      ensure
        Thread.current[InspectKey] = save
      end
    end

    # Adds +obj+ to the pretty printing buffer
    # using Object#pretty_print or Object#pretty_print_cycle.
    #
    # Object#pretty_print_cycle is used when +obj+ is already
    # printed, a.k.a the object reference chain has a cycle.
    def pp(obj)
      id = obj.__id__

      if Thread.current[InspectKey].include? id
        group {obj.pretty_print_cycle self}
        return
      end

      begin
        Thread.current[InspectKey] << id
        group {obj.pretty_print self}
      ensure
        Thread.current[InspectKey].pop unless PP.sharing_detection
      end
    end

    # A convenience method which is same as follows:
    #
    #   group(1, '#<' + obj.class.name, '>') { ... }
    def object_group(obj, &block) # :yield:
      group(1, '#<' + obj.class.name, '>', &block)
    end

    def object_address_group(obj, &block)
      id = "%x" % (obj.__id__ * 2)
      id.sub!(/\Af(?=[[:xdigit:]]{2}+\z)/, '') if id.sub!(/\A\.\./, '')
      group(1, "\#<#{obj.class}:0x#{id}", '>', &block)
    end

    # A convenience method which is same as follows:
    #
    #   text ','
    #   breakable
    def comma_breakable
      text ','
      breakable
    end

    # Adds a separated list.
    # The list is separated by comma with breakable space, by default.
    #
    # #seplist iterates the +list+ using +iter_method+.
    # It yields each object to the block given for #seplist.
    # The procedure +separator_proc+ is called between each yields.
    #
    # If the iteration is zero times, +separator_proc+ is not called at all.
    #
    # If +separator_proc+ is nil or not given,
    # +lambda { comma_breakable }+ is used.
    # If +iter_method+ is not given, :each is used.
    #
    # For example, following 3 code fragments has similar effect.
    #
    #   q.seplist([1,2,3]) {|v| xxx v }
    #
    #   q.seplist([1,2,3], lambda { comma_breakable }, :each) {|v| xxx v }
    #
    #   xxx 1
    #   q.comma_breakable
    #   xxx 2
    #   q.comma_breakable
    #   xxx 3
    def seplist(list, sep=nil, iter_method=:each) # :yield: element
      sep ||= lambda { comma_breakable }
      first = true
      list.__send__(iter_method) {|*v|
        if first
          first = false
        else
          sep.call
        end
        yield(*v)
      }
    end

    def pp_object(obj)
      object_address_group(obj) {
        seplist(obj.pretty_print_instance_variables, lambda { text ',' }) {|v|
          breakable
          v = v.to_s if Symbol === v
          text v
          text '='
          group(1) {
            breakable ''
            pp(obj.instance_eval(v))
          }
        }
      }
    end

    def pp_hash(obj)
      group(1, '{', '}') {
        seplist(obj, nil, :each_pair) {|k, v|
          group {
            pp k
            text '=>'
            group(1) {
              breakable ''
              pp v
            }
          }
        }
      }
    end
  end

  include PPMethods

  class SingleLine < PrettyPrint::SingleLine
    include PPMethods
  end

  module ObjectMixin
    # 1. specific pretty_print
    # 2. specific inspect
    # 3. specific to_s if instance variable is empty
    # 4. generic pretty_print

    # A default pretty printing method for general objects.
    # It calls #pretty_print_instance_variables to list instance variables.
    #
    # If +self+ has a customized (redefined) #inspect method,
    # the result of self.inspect is used but it obviously has no
    # line break hints.
    #
    # This module provides predefined #pretty_print methods for some of
    # the most commonly used built-in classes for convenience.
    def pretty_print(q)
      if /\(Kernel\)#/ !~ Object.instance_method(:method).bind(self).call(:inspect).inspect
        q.text self.inspect
      elsif /\(Kernel\)#/ !~ Object.instance_method(:method).bind(self).call(:to_s).inspect && instance_variables.empty?
        q.text self.to_s
      else
        q.pp_object(self)
      end
    end

    # A default pretty printing method for general objects that are
    # detected as part of a cycle.
    def pretty_print_cycle(q)
      q.object_address_group(self) {
        q.breakable
        q.text '...'
      }
    end

    # Returns a sorted array of instance variable names.
    #
    # This method should return an array of names of instance variables as symbols or strings as:
    # +[:@a, :@b]+.
    def pretty_print_instance_variables
      instance_variables.sort
    end

    # Is #inspect implementation using #pretty_print.
    # If you implement #pretty_print, it can be used as follows.
    #
    #   alias inspect pretty_print_inspect
    #
    # However, doing this requires that every class that #inspect is called on
    # implement #pretty_print, or a RuntimeError will be raised.
    def pretty_print_inspect
      if /\(PP::ObjectMixin\)#/ =~ Object.instance_method(:method).bind(self).call(:pretty_print).inspect
        raise "pretty_print is not overridden for #{self.class}"
      end
      PP.singleline_pp(self, '')
    end
  end
end

class Array
  def pretty_print(q)
    q.group(1, '[', ']') {
      q.seplist(self) {|v|
        q.pp v
      }
    }
  end

  def pretty_print_cycle(q)
    q.text(empty? ? '[]' : '[...]')
  end
end

class Hash
  def pretty_print(q)
    q.pp_hash self
  end

  def pretty_print_cycle(q)
    q.text(empty? ? '{}' : '{...}')
  end
end

class << ENV
  def pretty_print(q)
    q.pp_hash self
  end
end

class Struct
  def pretty_print(q)
    q.group(1, '#<struct ' + PP.mcall(self, Kernel, :class).name, '>') {
      q.seplist(PP.mcall(self, Struct, :members), lambda { q.text "," }) {|member|
        q.breakable
        q.text member.to_s
        q.text '='
        q.group(1) {
          q.breakable ''
          q.pp self[member]
        }
      }
    }
  end

  def pretty_print_cycle(q)
    q.text sprintf("#<struct %s:...>", PP.mcall(self, Kernel, :class).name)
  end
end

class Range
  def pretty_print(q)
    q.pp self.begin
    q.breakable ''
    q.text(self.exclude_end? ? '...' : '..')
    q.breakable ''
    q.pp self.end
  end
end

class File
  class Stat
    def pretty_print(q)
      require 'etc.so'
      q.object_group(self) {
        q.breakable
        q.text sprintf("dev=0x%x", self.dev); q.comma_breakable
        q.text "ino="; q.pp self.ino; q.comma_breakable
        q.group {
          m = self.mode
          q.text sprintf("mode=0%o", m)
          q.breakable
          q.text sprintf("(%s %c%c%c%c%c%c%c%c%c)",
            self.ftype,
            (m & 0400 == 0 ? ?- : ?r),
            (m & 0200 == 0 ? ?- : ?w),
            (m & 0100 == 0 ? (m & 04000 == 0 ? ?- : ?S) :
                             (m & 04000 == 0 ? ?x : ?s)),
            (m & 0040 == 0 ? ?- : ?r),
            (m & 0020 == 0 ? ?- : ?w),
            (m & 0010 == 0 ? (m & 02000 == 0 ? ?- : ?S) :
                             (m & 02000 == 0 ? ?x : ?s)),
            (m & 0004 == 0 ? ?- : ?r),
            (m & 0002 == 0 ? ?- : ?w),
            (m & 0001 == 0 ? (m & 01000 == 0 ? ?- : ?T) :
                             (m & 01000 == 0 ? ?x : ?t)))
        }
        q.comma_breakable
        q.text "nlink="; q.pp self.nlink; q.comma_breakable
        q.group {
          q.text "uid="; q.pp self.uid
          begin
            pw = Etc.getpwuid(self.uid)
          rescue ArgumentError
          end
          if pw
            q.breakable; q.text "(#{pw.name})"
          end
        }
        q.comma_breakable
        q.group {
          q.text "gid="; q.pp self.gid
          begin
            gr = Etc.getgrgid(self.gid)
          rescue ArgumentError
          end
          if gr
            q.breakable; q.text "(#{gr.name})"
          end
        }
        q.comma_breakable
        q.group {
          q.text sprintf("rdev=0x%x", self.rdev)
          q.breakable
          q.text sprintf('(%d, %d)', self.rdev_major, self.rdev_minor)
        }
        q.comma_breakable
        q.text "size="; q.pp self.size; q.comma_breakable
        q.text "blksize="; q.pp self.blksize; q.comma_breakable
        q.text "blocks="; q.pp self.blocks; q.comma_breakable
        q.group {
          t = self.atime
          q.text "atime="; q.pp t
          q.breakable; q.text "(#{t.tv_sec})"
        }
        q.comma_breakable
        q.group {
          t = self.mtime
          q.text "mtime="; q.pp t
          q.breakable; q.text "(#{t.tv_sec})"
        }
        q.comma_breakable
        q.group {
          t = self.ctime
          q.text "ctime="; q.pp t
          q.breakable; q.text "(#{t.tv_sec})"
        }
      }
    end
  end
end

class MatchData
  def pretty_print(q)
    q.object_group(self) {
      q.breakable
      q.seplist(1..self.size, lambda { q.breakable }) {|i|
        q.pp self[i-1]
      }
    }
  end
end

class Object
  include PP::ObjectMixin
end

[Numeric, Symbol, FalseClass, TrueClass, NilClass, Module].each {|c|
  c.class_eval {
    def pretty_print_cycle(q)
      q.text inspect
    end
  }
}

[Numeric, FalseClass, TrueClass, Module].each {|c|
  c.class_eval {
    def pretty_print(q)
      q.text inspect
    end
  }
}

# :enddoc:
if __FILE__ == $0
  require 'test/unit'

  class PPTest < Test::Unit::TestCase
    def test_list0123_12
      assert_equal("[0, 1, 2, 3]\n", PP.pp([0,1,2,3], '', 12))
    end

    def test_list0123_11
      assert_equal("[0,\n 1,\n 2,\n 3]\n", PP.pp([0,1,2,3], '', 11))
    end

    OverriddenStruct = Struct.new("OverriddenStruct", :members, :class)
    def test_struct_override_members # [ruby-core:7865]
      a = OverriddenStruct.new(1,2)
      assert_equal("#<struct Struct::OverriddenStruct members=1, class=2>\n", PP.pp(a, ''))
    end

    def test_redefined_method
      o = ""
      def o.method
      end
      assert_equal(%(""\n), PP.pp(o, ""))
    end
  end

  class HasInspect
    def initialize(a)
      @a = a
    end

    def inspect
      return "<inspect:#{@a.inspect}>"
    end
  end

  class HasPrettyPrint
    def initialize(a)
      @a = a
    end

    def pretty_print(q)
      q.text "<pretty_print:"
      q.pp @a
      q.text ">"
    end
  end

  class HasBoth
    def initialize(a)
      @a = a
    end

    def inspect
      return "<inspect:#{@a.inspect}>"
    end

    def pretty_print(q)
      q.text "<pretty_print:"
      q.pp @a
      q.text ">"
    end
  end

  class PrettyPrintInspect < HasPrettyPrint
    alias inspect pretty_print_inspect
  end

  class PrettyPrintInspectWithoutPrettyPrint
    alias inspect pretty_print_inspect
  end

  class PPInspectTest < Test::Unit::TestCase
    def test_hasinspect
      a = HasInspect.new(1)
      assert_equal("<inspect:1>\n", PP.pp(a, ''))
    end

    def test_hasprettyprint
      a = HasPrettyPrint.new(1)
      assert_equal("<pretty_print:1>\n", PP.pp(a, ''))
    end

    def test_hasboth
      a = HasBoth.new(1)
      assert_equal("<pretty_print:1>\n", PP.pp(a, ''))
    end

    def test_pretty_print_inspect
      a = PrettyPrintInspect.new(1)
      assert_equal("<pretty_print:1>", a.inspect)
      a = PrettyPrintInspectWithoutPrettyPrint.new
      assert_raise(RuntimeError) { a.inspect }
    end

    def test_proc
      a = proc {1}
      assert_equal("#{a.inspect}\n", PP.pp(a, ''))
    end

    def test_to_s_with_iv
      a = Object.new
      def a.to_s() "aaa" end
      a.instance_eval { @a = nil }
      result = PP.pp(a, '')
      assert_equal("#{a.inspect}\n", result)
      assert_match(/\A#<Object.*>\n\z/m, result)
      a = 1.0
      a.instance_eval { @a = nil }
      result = PP.pp(a, '')
      assert_equal("#{a.inspect}\n", result)
    end

    def test_to_s_without_iv
      a = Object.new
      def a.to_s() "aaa" end
      result = PP.pp(a, '')
      assert_equal("#{a.inspect}\n", result)
      assert_equal("aaa\n", result)
    end
  end

  class PPCycleTest < Test::Unit::TestCase
    def test_array
      a = []
      a << a
      assert_equal("[[...]]\n", PP.pp(a, ''))
      assert_equal("#{a.inspect}\n", PP.pp(a, ''))
    end

    def test_hash
      a = {}
      a[0] = a
      assert_equal("{0=>{...}}\n", PP.pp(a, ''))
      assert_equal("#{a.inspect}\n", PP.pp(a, ''))
    end

    S = Struct.new("S", :a, :b)
    def test_struct
      a = S.new(1,2)
      a.b = a
      assert_equal("#<struct Struct::S a=1, b=#<struct Struct::S:...>>\n", PP.pp(a, ''))
      assert_equal("#{a.inspect}\n", PP.pp(a, ''))
    end

    def test_object
      a = Object.new
      a.instance_eval {@a = a}
      assert_equal(a.inspect + "\n", PP.pp(a, ''))
    end

    def test_anonymous
      a = Class.new.new
      assert_equal(a.inspect + "\n", PP.pp(a, ''))
    end

    def test_withinspect
      a = []
      a << HasInspect.new(a)
      assert_equal("[<inspect:[...]>]\n", PP.pp(a, ''))
      assert_equal("#{a.inspect}\n", PP.pp(a, ''))
    end

    def test_share_nil
      begin
        PP.sharing_detection = true
        a = [nil, nil]
        assert_equal("[nil, nil]\n", PP.pp(a, ''))
      ensure
        PP.sharing_detection = false
      end
    end
  end

  class PPSingleLineTest < Test::Unit::TestCase
    def test_hash
      assert_equal("{1=>1}", PP.singleline_pp({ 1 => 1}, '')) # [ruby-core:02699]
      assert_equal("[1#{', 1'*99}]", PP.singleline_pp([1]*100, ''))
    end
  end
end
