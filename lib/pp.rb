# $Id$

=begin
= Pretty-printer for Ruby objects.

== Which seems better?

non-pretty-printed output by (({p})) is:
  #<PP:0x81a0d10 @stack=[], @genspace=#<Proc:0x81a0cc0>, @nest=[0], @newline="\n", @buf=#<PrettyPrint::Group:0x81a0c98 @group=0, @tail=0, @buf=[#<PrettyPrint::Group:0x81a0ba8 @group=1, @tail=0, @buf=[#<PrettyPrint::Text:0x81a0b30 @tail=2, @width=1, @text="[">, #<PrettyPrint::Group:0x81a0a68 @group=2, @tail=1, @buf=[#<PrettyPrint::Text:0x81a09f0 @tail=1, @width=1, @text="1">], @singleline_width=1>, #<PrettyPrint::Text:0x81a0a7c @tail=0, @width=1, @text=",">, #<PrettyPrint::Breakable:0x81a0a2c @group=2, @genspace=#<Proc:0x81a0cc0>, @newline="\n", @indent=1, @tail=2, @sep=" ", @width=1>, #<PrettyPrint::Group:0x81a09c8 @group=2, @tail=1, @buf=[#<PrettyPrint::Text:0x81a0950 @tail=1, @width=1, @text="2">], @singleline_width=1>, #<PrettyPrint::Text:0x81a0af4 @tail=0, @width=1, @text="]">], @singleline_width=6>], @singleline_width=6>, @sharing_detection=false>

pretty-printed output by (({pp})) is:
  #<PP:0x40d0688
   @buf=
    #<PrettyPrint::Group:0x40d064c
     @buf=
      [#<PrettyPrint::Group:0x40d05d4
        @buf=
         [#<PrettyPrint::Text:0x40d0598 @tail=2, @text="[", @width=1>,
          #<PrettyPrint::Group:0x40d0534
           @buf=[#<PrettyPrint::Text:0x40d04f8 @tail=1, @text="1", @width=1>],
           @group=2,
           @singleline_width=1,
           @tail=1>,
          #<PrettyPrint::Text:0x40d053e @tail=0, @text=",", @width=1>,
          #<PrettyPrint::Breakable:0x40d0516
           @genspace=#<Proc:0x40d0656>,
           @group=2,
           @indent=1,
           @newline="\n",
           @sep=" ",
           @tail=2,
           @width=1>,
          #<PrettyPrint::Group:0x40d04e4
           @buf=[#<PrettyPrint::Text:0x40d04a8 @tail=1, @text="2", @width=1>],
           @group=2,
           @singleline_width=1,
           @tail=1>,
          #<PrettyPrint::Text:0x40d057a @tail=0, @text="]", @width=1>],
        @group=1,
        @singleline_width=6,
        @tail=0>],
     @group=0,
     @singleline_width=6,
     @tail=0>,
   @genspace=#<Proc:0x40d0656>,
   @nest=[0],
   @newline="\n",
   @sharing_detection=false,
   @stack=[]>

I like the latter.  If you do too, this library is for you.

== Usage

: pp(obj)
    output ((|obj|)) to (({$>})) in pretty printed format.

    It returns (({nil})).

== Output Customization
To define your customized pretty printing function for your classes,
redefine a method (({pretty_print(((|pp|)))})) in the class.
It takes an argument ((|pp|)) which is an instance of the class ((<PP>)).
The method should use PP#text, PP#breakable, PP#nest, PP#group and
PP#pp to print the object.

= PP
== super class
((<PrettyPrint>))

== class methods
--- PP.pp(obj[, out[, width]])
    outputs ((|obj|)) to ((|out|)) in pretty printed format of
    ((|width|)) columns in width.

    If ((|out|)) is ommitted, (({$>})) is assumed.
    If ((|width|)) is ommitted, 79 is assumed.

    PP.pp returns ((|out|)).

--- PP.sharing_detection
    returns the sharing detection flag as boolean value.
    It is false by default.

--- PP.sharing_detection = boolean_value
    sets the sharing detection flag.

== methods
--- pp(obj)
    adds ((|obj|)) to the pretty printing buffer
    using Object#pretty_print or Object#pretty_print_cycle.

    Object#pretty_print_cycle is used when ((|obj|)) is already
    printed, a.k.a the object reference chain has a cycle.

--- object_group(obj) { ... }
    is a convenience method which is same as follows:

      group(1, '#<' + obj.class.name, '>') { ... }

--- comma_breakable
    is a convenience method which is same as follows:

      text ','
      breakable

= Object
--- pretty_print(pp)
    is a default pretty printing method for general objects.
    It calls (({pretty_print_instance_variables})) to list instance variables.

    If (({self})) has a customized (redefined) (({inspect})) method,
    the result of (({self.inspect})) is used but it obviously has no
    line break hints.

    This module provides predefined pretty_print() methods for some of
    the most commonly used built-in classes for convenience.

--- pretty_print_cycle(pp)
    is a default pretty printing method for general objects that are
    detected as part of a cycle.

--- pretty_print_instance_variables
    returns a sorted array of instance variable names.

    This method should return an array of names of instance variables as symbols or strings as:
    (({[:@a, :@b]})).
=end

require 'prettyprint'

module Kernel
  private
  def pp(*objs)
    objs.each {|obj|
      PP.pp(obj)
    }
    nil
  end
end

class PP < PrettyPrint
  def PP.pp(obj, out=$>, width=79)
    pp = PP.new(out, width)
    pp.guard_inspect_key {pp.pp obj}
    pp.flush
    #$pp = pp
    out << "\n"
  end

  @@sharing_detection = false
  def PP.sharing_detection
    return @@sharing_detection
  end

  def PP.sharing_detection=(val)
    @@sharing_detection = val
  end

  def initialize(out, width=79)
    super
    @sharing_detection = @@sharing_detection
  end

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
      Thread.current[InspectKey].pop unless @sharing_detection
    end
  end

  def object_group(obj, &block)
    group(1, '#<' + obj.class.name, '>', &block)
  end

  def object_address_group(obj, &block)
    group(1, sprintf('#<%s:0x%x', obj.class.name, obj.__id__ * 2), '>', &block)
  end

  def comma_breakable
    text ','
    breakable
  end

  def pp_object(obj)
    object_address_group(obj) {
      obj.pretty_print_instance_variables.each {|v|
        v = v.to_s if Symbol === v
        text ',' unless first?
        breakable
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
      obj.each {|k, v|
        comma_breakable unless first?
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

  module ObjectMixin
    # 1. specific pretty_print
    # 2. specific inspect
    # 3. generic pretty_print

    Key = :__pp_instead_of_inspect__

    def pretty_print(pp)
      # specific pretty_print is not defined, try specific inspect.
      begin
        old = Thread.current[Key]
        result1 = sprintf('#<%s:0x%x pretty_printed>', self.class.name, self.__id__ * 2)
        Thread.current[Key] = [pp, result1]
        result2 = ObjectMixin.pp_call_inspect(self)
      ensure
        Thread.current[Key] = old
      end

      unless result1.equal? result2
        pp.text result2
      end
    end

    def ObjectMixin.pp_call_inspect(obj); obj.inspect; end
    CallInspectFrame = "#{__FILE__}:#{__LINE__ - 1}:in `pp_call_inspect'"

    def inspect
      if CallInspectFrame == caller[0]
        # specific inspect is also not defined, use generic pretty_print. 
        pp, result = Thread.current[Key]
        pp.pp_object(self)
        result
      else
        super
      end
    end

    def pretty_print_cycle(pp)
      pp.object_address_group(self) {
        pp.breakable
        pp.text '...'
      }
    end

    def pretty_print_instance_variables
      instance_variables.sort
    end
  end
end

[Numeric, FalseClass, TrueClass, Module].each {|c|
  c.class_eval {
    def pretty_print(pp)
      pp.text self.to_s
    end
  }
}

class Array
  def pretty_print(pp)
    pp.group(1, '[', ']') {
      self.each {|v|
        pp.comma_breakable unless pp.first?
        pp.pp v
      }
    }
  end

  def pretty_print_cycle(pp)
    pp.text(empty? ? '[]' : '[...]')
  end
end

class Hash
  def pretty_print(pp)
    pp.pp_hash self
  end

  def pretty_print_cycle(pp)
    pp.text(empty? ? '{}' : '{...}')
  end
end

class << ENV
  def pretty_print(pp)
    pp.pp_hash self
  end
end

class Struct
  def pretty_print(pp)
    pp.object_group(self) {
      self.members.each {|member|
        pp.text "," unless pp.first?
        pp.breakable
        pp.text member.to_s
        pp.text '='
        pp.group(1) {
          pp.breakable ''
          pp.pp self[member]
        }
      }
    }
  end

  def pretty_print_cycle(pp)
    pp.text sprintf("#<%s:...>", self.class.name)
  end
end

class Range
  def pretty_print(pp)
    pp.pp self.begin
    pp.breakable ''
    pp.text(self.exclude_end? ? '...' : '..')
    pp.breakable ''
    pp.pp self.end
  end
end

class File
  class Stat
    def pretty_print(pp)
      require 'etc.so'
      pp.object_group(self) {
        pp.breakable
        pp.text sprintf("dev=0x%x", self.dev); pp.comma_breakable
        pp.text "ino="; pp.pp self.ino; pp.comma_breakable
        pp.group {
          m = self.mode
          pp.text sprintf("mode=0%o", m)
          pp.breakable
          pp.text sprintf("(%s %c%c%c%c%c%c%c%c%c)",
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
        pp.comma_breakable
        pp.text "nlink="; pp.pp self.nlink; pp.comma_breakable
        pp.group {
          pp.text "uid="; pp.pp self.uid
          begin
            name = Etc.getpwuid(self.uid).name
            pp.breakable; pp.text "(#{name})"
          rescue ArgumentError
          end
        }
        pp.comma_breakable
        pp.group {
          pp.text "gid="; pp.pp self.gid
          begin
            name = Etc.getgrgid(self.gid).name
            pp.breakable; pp.text "(#{name})"
          rescue ArgumentError
          end
        }
        pp.comma_breakable
        pp.group {
          pp.text sprintf("rdev=0x%x", self.rdev)
          pp.breakable
          pp.text sprintf('(%d, %d)', self.rdev_major, self.rdev_minor)
        }
        pp.comma_breakable
        pp.text "size="; pp.pp self.size; pp.comma_breakable
        pp.text "blksize="; pp.pp self.blksize; pp.comma_breakable
        pp.text "blocks="; pp.pp self.blocks; pp.comma_breakable
        pp.group {
          t = self.atime
          pp.text "atime="; pp.pp t
          pp.breakable; pp.text "(#{t.tv_sec})"
        }
        pp.comma_breakable
        pp.group {
          t = self.mtime
          pp.text "mtime="; pp.pp t
          pp.breakable; pp.text "(#{t.tv_sec})"
        }
        pp.comma_breakable
        pp.group {
          t = self.ctime
          pp.text "ctime="; pp.pp t
          pp.breakable; pp.text "(#{t.tv_sec})"
        }
      }
    end
  end
end

class << ARGF
  def pretty_print(pp)
    pp.text self.to_s
  end
end

class Object
  include PP::ObjectMixin
end

[Numeric, Symbol, FalseClass, TrueClass, NilClass, Module].each {|c|
  c.class_eval {
    alias :pretty_print_cycle :pretty_print
  }
}

if __FILE__ == $0
  require 'runit/testcase'
  require 'runit/cui/testrunner'

  class PPTest < RUNIT::TestCase
    def test_list0123_12
      assert_equal("[0, 1, 2, 3]\n", PP.pp([0,1,2,3], '', 12))
    end

    def test_list0123_11
      assert_equal("[0,\n 1,\n 2,\n 3]\n", PP.pp([0,1,2,3], '', 11))
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

    def pretty_print(pp)
      pp.text "<pretty_print:"
      pp.pp @a
      pp.text ">"
    end
  end

  class HasBoth
    def initialize(a)
      @a = a
    end

    def inspect
      return "<inspect:#{@a.inspect}>"
    end

    def pretty_print(pp)
      pp.text "<pretty_print:"
      pp.pp @a
      pp.text ">"
    end
  end

  class PPInspectTest < RUNIT::TestCase
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
  end

  class PPCycleTest < RUNIT::TestCase
    def test_array
      a = []
      a << a
      assert_equal("[[...]]\n", PP.pp(a, ''))
    end

    def test_hash
      a = {}
      a[0] = a
      assert_equal("{0=>{...}}\n", PP.pp(a, ''))
    end

    S = Struct.new("S", :a, :b)
    def test_struct
      a = S.new(1,2)
      a.b = a
      assert_equal("#<Struct::S a=1, b=#<Struct::S:...>>\n", PP.pp(a, ''))
    end

    def test_object
      a = Object.new
      a.instance_eval {@a = a}
      assert_equal(a.inspect + "\n", PP.pp(a, ''))
    end

    def test_withinspect
      a = []
      a << HasInspect.new(a)
      assert_equal("[<inspect:[...]>]\n", PP.pp(a, ''))
    end
  end

  RUNIT::CUI::TestRunner.run(PPTest.suite)
  RUNIT::CUI::TestRunner.run(PPInspectTest.suite)
  RUNIT::CUI::TestRunner.run(PPCycleTest.suite)
end
