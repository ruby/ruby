# C0 coverage of each instructions

# :NOTE: This is for development purpose; never consider this file as
# ISeq compilation specification.

begin
  # This library brings some additional coverage.
  # Not mandatory.
  require 'rbconfig/sizeof'
rescue LoadError
  # OK, just skip
else
  if defined? RbConfig::LIMITS
    $FIXNUM_MAX = RbConfig::LIMITS["FIXNUM_MAX"]
    $FIXNUM_MIN = RbConfig::LIMITS["FIXNUM_MIN"]
  end
end

fsl   = { frozen_string_literal: true } # used later
tests = [
  # insn ,   expression to generate such insn
  [ 'nop',   %q{ raise rescue true }, ],

  [ 'setlocal *, 0', %q{ x = true }, ],
  [ 'setlocal *, 1', %q{ x = nil; -> { x = true }.call }, ],
  [ 'setlocal',      %q{ x = nil; -> { -> { x = true }.() }.() }, ],
  [ 'getlocal *, 0', %q{ x = true; x }, ],
  [ 'getlocal *, 1', %q{ x = true; -> { x }.call }, ],
  [ 'getlocal',      %q{ x = true; -> { -> { x }.() }.() }, ],

  [ 'setblockparam', <<-'},', ], # {
    def m&b
      b = # here
        proc { true }
    end
    m { false }.call
  },
  [ 'getblockparam', <<-'},', ], # {
    def m&b
      b # here
    end
    m { true }.call
  },
  [ 'getblockparamproxy', <<-'},', ], # {
    def m&b
      b # here
        .call
    end
    m { true }
  },

  [ 'setspecial', %q{ true if true..true }, ],
  [ 'getspecial', %q{ $&.nil? }, ],
  [ 'getspecial', %q{ $`.nil? }, ],
  [ 'getspecial', %q{ $'.nil? }, ],
  [ 'getspecial', %q{ $+.nil? }, ],
  [ 'getspecial', %q{ $1.nil? }, ],
  [ 'getspecial', %q{ $128.nil? }, ],

  [ 'getglobal', %q{ String === $0 }, ],
  [ 'getglobal', %q{ $_.nil? }, ],
  [ 'setglobal', %q{ $0 = "true" }, ],

  [ 'setinstancevariable', %q{ @x = true }, ],
  [ 'getinstancevariable', %q{ @x = true; @x }, ],

  [ 'setclassvariable', %q{ class A; @@x = true; end }, ],
  [ 'getclassvariable', %q{ class A; @@x = true; @@x end }, ],

  [ 'setconstant', %q{ X = true }, ],
  [ 'setconstant', %q{ Object::X = true }, ],
  [ 'getconstant', %q{ X = true; X }, ],
  [ 'getconstant', %q{ X = true; Object::X }, ],

  [ 'getinlinecache / setinlinecache', %q{ def x; X; end; X = true; x; x; x }, ],

  [ 'putnil',               %q{ $~ == nil }, ],
  [ 'putself',              %q{ $~ != self }, ],
  [ 'putobject INT2FIX(0)', %q{ $~ != 0 }, ],
  [ 'putobject INT2FIX(1)', %q{ $~ != 1 }, ],
  [ 'putobject',            %q{ $~ != -1 }, ],
  [ 'putobject',            %q{ $~ != /x/ }, ],
  [ 'putobject',            %q{ $~ != :x }, ],
  [ 'putobject',            %q{ $~ != (1..2) }, ],
  [ 'putobject',            %q{ $~ != true }, ],
  [ 'putobject',            %q{ /(?<x>x)/ =~ "x"; x == "x" }, ],

  [ 'putspecialobject',         %q{ {//=>true}[//] }, ],
  [ 'putstring',                %q{ "true" }, ],
  [ 'tostring / concatstrings', %q{ "#{true}" }, ],
  [ 'toregexp',                 %q{ /#{true}/ =~ "true" && $~ }, ],
  [ 'intern',                   %q{ :"#{true}" }, ],

  [ 'newarray',    %q{ ["true"][0] }, ],
  [ 'newarraykwsplat', %q{ [**{x:'true'}][0][:x] }, ],
  [ 'duparray',    %q{ [ true ][0] }, ],
  [ 'expandarray', %q{ y = [ true, false, nil ]; x, = y; x }, ],
  [ 'expandarray', %q{ y = [ true, false, nil ]; x, *z = y; x }, ],
  [ 'expandarray', %q{ y = [ true, false, nil ]; x, *z, w = y; x }, ],
  [ 'splatarray',  %q{ x, = *(y = true), false; x }, ],
  [ 'concatarray', %q{ ["t", "r", *x = "u", "e"].join }, ],
  [ 'concatarray', <<-'},', ],  # {
    class X; def to_a; ['u']; end; end
    ['t', 'r', *X.new, 'e'].join
  },
  [ 'concatarray', <<-'},', ],  # {
    r = false
    t = [true, nil]
    q, w, e = r, *t             # here
    w
  },

  [ 'newhash',  %q{ x = {}; x[x] = true }, ],
  [ 'newhash',  %q{ x = true; { x => x }[x] }, ],
  [ 'newhashfromarray', %q{ { a: true }[:a] }, ],
  [ 'newrange', %q{ x = 1; [*(0..x)][0] == 0 }, ],
  [ 'newrange', %q{ x = 1; [*(0...x)][0] == 0 }, ],

  [ 'pop',     %q{ def x; true; end; x }, ],
  [ 'dup',     %q{ x = y = true; x }, ],
  [ 'dupn',    %q{ Object::X ||= true }, ],
  [ 'reverse', %q{ q, (w, e), r = 1, [2, 3], 4; e == 3 }, ],
  [ 'swap',    <<-'},', ],      # {
    x = [[false, true]]
    for i, j in x               # here
      ;
    end
    j
  },

  [ 'topn',        %q{ x, y = [], 0; x[*y], = [true, false]; x[0] }, ],
  [ 'setn',        %q{ x, y = [], 0; x[*y]  =  true        ; x[0] }, ],
  [ 'adjuststack', %q{ x = [true]; x[0] ||= nil; x[0] }, ],

  [ 'defined',      %q{ !defined?(x) }, ],
  [ 'checkkeyword', %q{ def x x:rand;x end; x x: true }, ],
  [ 'checktype',    %q{ x = true; "#{x}" }, ],
  [ 'checkmatch',   <<-'},', ], # {
    x = y = true
    case x
    when false
      y = false
    when true                   # here
      y = nil
    end
    y == nil
  },
  [ 'checkmatch',   <<-'},', ], # {
    x, y = true, [false]
    case x
    when *y                     # here
      z = false
    else
      z = true
    end
    z
  },
  [ 'checkmatch',   <<-'},', ], # {
    x = false
    begin
      raise
    rescue                      # here
      x = true
    end
    x
  },

  [ 'defineclass', %q{                 module X;    true end }, ],
  [ 'defineclass', %q{ X = Module.new; module X;    true end }, ],
  [ 'defineclass', %q{                 class X;     true end }, ],
  [ 'defineclass', %q{ X = Class.new;  class X;     true end }, ],
  [ 'defineclass', %q{ X = Class.new;  class Y < X; true end }, ],
  [ 'defineclass', %q{ X = Class.new;  class << X;  true end }, ],
  [ 'defineclass', <<-'},', ], # {
    X = Class.new
    Y = Class.new(X)
    class Y < X
      true
    end
  },

  [ 'opt_send_without_block', %q{ true.to_s }, ],
  [ 'send',                   %q{ true.tap {|i| i.to_s } }, ],
  [ 'opt_sendsym_without_block', %q{ true.__send__("to_s".to_sym) }, ],
  [ 'sendsym',                   %q{ true.__send__("tap".to_sym) {|i| i.to_s } }, ],
  [ 'leave',                  %q{ def x; true; end; x }, ],
  [ 'invokesuper',            <<-'},', ], # {
    class X < String
      def empty?
        super                   # here
      end
    end
   X.new.empty?
  },
  [ 'invokeblock',            <<-'},', ], # {
    def x
      return yield self         # here
    end
    x do
      true
    end
  },

  [ 'opt_str_freeze', %q{ 'true'.freeze }, ],
  [ 'opt_nil_p',      %q{ nil.nil? }, ],
  [ 'opt_nil_p',      %q{ !Object.nil? }, ],
  [ 'opt_nil_p',      %q{ Class.new{def nil?; true end}.new.nil? }, ],
  [ 'opt_str_uminus', %q{ -'true' }, ],
  [ 'opt_str_freeze', <<-'},', ], # {
    class String
      def freeze
        true
      end
    end
    'true'.freeze
  },

  [ 'opt_newarray_max', %q{ [ ].max.nil? }, ],
  [ 'opt_newarray_max', %q{ [1, x = 2, 3].max == 3 }, ],
  [ 'opt_newarray_max', <<-'},', ], # {
    class Array
      def max
        true
      end
    end
    [1, x = 2, 3].max
  },
  [ 'opt_newarray_min', %q{ [ ].min.nil? }, ],
  [ 'opt_newarray_min', %q{ [3, x = 2, 1].min == 1 }, ],
  [ 'opt_newarray_min', <<-'},', ], # {
    class Array
      def min
        true
      end
    end
    [3, x = 2, 1].min
  },

  [ 'throw',        %q{ false.tap { break true } }, ],
  [ 'branchif',     %q{ x = nil;  x ||= true }, ],
  [ 'branchif',     %q{ x = true; x ||= nil; x }, ],
  [ 'branchunless', %q{ x = 1;    x &&= true }, ],
  [ 'branchunless', %q{ x = nil;  x &&= true; x.nil? }, ],
  [ 'branchnil',    %q{ x = true; x&.to_s }, ],
  [ 'branchnil',    %q{ x = nil;  (x&.to_s).nil? }, ],
  [ 'jump',         <<-'},', ], # {
    y = 1
    x = if y == 0 then nil elsif y == 1 then true else nil end
    x
  },
  [ 'jump',         <<-'},', ], # {
    # ultra complicated situation: this ||= assignment only generates
    # 15 instructions, not including the class definition.
    class X; attr_accessor :x; end
    x = X.new
    x&.x ||= true               # here
  },

  [ 'once', %q{ /#{true}/o =~ "true" && $~ }, ],
  [ 'once', <<-'},', ],         # {
    def once expr
      return /#{expr}/o         # here
    end
    x = once(true); x = once(false); x = once(nil);
    x =~ "true" && $~
  },
  [ 'once', <<-'},', ],         # {
    # recursive once
    def once n
      return %r/#{
        if n == 0
          true
        else
          once(n-1)             # here
        end
      }/ox
    end
    x = once(128); x = once(7); x = once(16);
    x =~ "true" && $~
  },
  [ 'once', <<-'},', ],         # {
    # inter-thread lockup situation
    def once n
      return Thread.start n do |m|
        Thread.pass
        next %r/#{
          sleep m               # here
          true
        }/ox
      end
    end
    x = once(1); y = once(0.1); z = y.value
    z =~ "true" && $~
  },

  [ 'opt_case_dispatch', %q{ case   0 when 1.1 then false else true end }, ],
  [ 'opt_case_dispatch', %q{ case 1.0 when 1.1 then false else true end }, ],

  [ 'opt_plus',    %q{ 1 + 1 == 2 }, ],
  if defined? $FIXNUM_MAX then
    [ 'opt_plus',  %Q{ #{ $FIXNUM_MAX } + 1 == #{ $FIXNUM_MAX + 1 } }, ]
  end,
  [ 'opt_plus',    %q{ 1.0 + 1.0 == 2.0 }, ],
  [ 'opt_plus',    %q{ x = +0.0.next_float; x + x >= x }, ],
  [ 'opt_plus',    %q{ 't' + 'rue' }, ],
  [ 'opt_plus',    %q{ ( ['t'] + ['r', ['u', ['e'], ], ] ).join }, ],
  [ 'opt_plus',    %q{ Time.at(1) + 1 == Time.at(2) }, ],
  [ 'opt_minus',   %q{ 1 - 1 == 0 }, ],
  if defined? $FIXNUM_MIN then
    [ 'opt_minus', %Q{ #{ $FIXNUM_MIN } - 1 == #{ $FIXNUM_MIN - 1 } }, ]
  end,
  [ 'opt_minus',   %q{ 1.0 - 1.0 == 0.0 }, ],
  [ 'opt_minus',   %q{ x = -0.0.prev_float; x - x == 0.0 }, ],
  [ 'opt_minus',   %q{ ( [false, true] - [false] )[0] }, ],
  [ 'opt_mult',    %q{ 1 * 1 == 1 }, ],
  [ 'opt_mult',    %q{ 1.0 * 1.0 == 1.0 }, ],
  [ 'opt_mult',    %q{ x = +0.0.next_float; x * x <= x }, ],
  [ 'opt_mult',    %q{ ( "ruet" * 3 )[7,4] }, ],
  [ 'opt_div',     %q{ 1 / 1 == 1 }, ],
  [ 'opt_div',     %q{ 1.0 / 1.0 == 1.0 }, ],
  [ 'opt_div',     %q{ x = +0.0.next_float; x / x >= x }, ],
  [ 'opt_div',     %q{ x = 1/2r; x / x == 1 }, ],
  [ 'opt_mod',     %q{ 1 % 1 == 0 }, ],
  [ 'opt_mod',     %q{ 1.0 % 1.0 == 0.0 }, ],
  [ 'opt_mod',     %q{ x = +0.0.next_float; x % x == 0.0 }, ],
  [ 'opt_mod',     %q{ '%s' % [ true ] }, ],

  [ 'opt_eq', %q{ 1 == 1 }, ],
  [ 'opt_eq', <<-'},', ],       # {
    class X; def == other; true; end; end
    X.new == true
  },
  [ 'opt_neq', %q{ 1 != 0 }, ],
  [ 'opt_neq', <<-'},', ],       # {
    class X; def != other; true; end; end
    X.new != true
  },

  [ 'opt_lt', %q{            -1   <  0 }, ],
  [ 'opt_lt', %q{            -1.0 <  0.0 }, ],
  [ 'opt_lt', %q{ -0.0.prev_float <  0.0 }, ],
  [ 'opt_lt', %q{              ?a <  ?z }, ],
  [ 'opt_le', %q{            -1   <= 0 }, ],
  [ 'opt_le', %q{            -1.0 <= 0.0 }, ],
  [ 'opt_le', %q{ -0.0.prev_float <= 0.0 }, ],
  [ 'opt_le', %q{              ?a <= ?z }, ],
  [ 'opt_gt', %q{             1   >  0 }, ],
  [ 'opt_gt', %q{             1.0 >  0.0 }, ],
  [ 'opt_gt', %q{ +0.0.next_float >  0.0 }, ],
  [ 'opt_gt', %q{              ?z >  ?a }, ],
  [ 'opt_ge', %q{             1   >= 0 }, ],
  [ 'opt_ge', %q{             1.0 >= 0.0 }, ],
  [ 'opt_ge', %q{ +0.0.next_float >= 0.0 }, ],
  [ 'opt_ge', %q{              ?z >= ?a }, ],

  [ 'opt_ltlt', %q{  '' << 'true' }, ],
  [ 'opt_ltlt', %q{ ([] << 'true').join }, ],
  [ 'opt_ltlt', %q{ (1 << 31) == 2147483648 }, ],

  [ 'opt_aref', %q{ ['true'][0] }, ],
  [ 'opt_aref', %q{ { 0 => 'true'}[0] }, ],
  [ 'opt_aref', %q{ 'true'[0] == ?t }, ],
  [ 'opt_aset', %q{ [][0] = true }, ],
  [ 'opt_aset', %q{ {}[0] = true }, ],
  [ 'opt_aset', %q{ x = 'frue'; x[0] = 't'; x }, ],
  [ 'opt_aset', <<-'},', ], # {
    # opt_aref / opt_aset mixup situation
    class X; def x; {}; end; end
    x = X.new
    x&.x[true] ||= true         # here
  },

  [ 'opt_aref_with', %q{ { 'true' => true }['true'] }, ],
  [ 'opt_aref_with', %q{ Struct.new(:nil).new['nil'].nil? }, ],
  [ 'opt_aset_with', %q{ {}['true'] = true }, ],
  [ 'opt_aset_with', %q{ Struct.new(:true).new['true'] = true }, ],

  [ 'opt_length',  %q{   'true'       .length == 4 }, ],
  [ 'opt_length',  %q{   :true        .length == 4 }, ],
  [ 'opt_length',  %q{ [ 'true' ]     .length == 1 }, ],
  [ 'opt_length',  %q{ { 'true' => 1 }.length == 1 }, ],
  [ 'opt_size',    %q{   'true'       .size   == 4 }, ],
  [ 'opt_size',    %q{               1.size   >= 4 }, ],
  [ 'opt_size',    %q{ [ 'true' ]     .size   == 1 }, ],
  [ 'opt_size',    %q{ { 'true' => 1 }.size   == 1 }, ],
  [ 'opt_empty_p', %q{ ''.empty? }, ],
  [ 'opt_empty_p', %q{ [].empty? }, ],
  [ 'opt_empty_p', %q{ {}.empty? }, ],
  [ 'opt_empty_p', %q{ Queue.new.empty? }, ],

  [ 'opt_succ',  %q{ 1.succ == 2 }, ],
  if defined? $FIXNUM_MAX then
    [ 'opt_succ',%Q{ #{ $FIXNUM_MAX }.succ == #{ $FIXNUM_MAX + 1 } }, ]
  end,
  [ 'opt_succ',  %q{ '1'.succ == '2' }, ],
  [ 'opt_succ',  %q{ x = Time.at(0); x.succ == Time.at(1) }, ],

  [ 'opt_not',  %q{ ! false }, ],
  [ 'opt_neq', <<-'},', ],       # {
    class X; def !; true; end; end
    ! X.new
  },

  [ 'opt_regexpmatch2',  %q{ /true/ =~ 'true' && $~ }, ],
  [ 'opt_regexpmatch2', <<-'},', ],       # {
    class Regexp; def =~ other; true; end; end
    /true/ =~ 'true'
  },
  [ 'opt_regexpmatch2',  %q{ 'true' =~ /true/ && $~ }, ],
  [ 'opt_regexpmatch2', <<-'},', ],       # {
    class String; def =~ other; true; end; end
    'true' =~ /true/
  },
]

# normal path
tests.compact.each do |(insn, expr, *a)|
  if a.last.is_a?(Hash)
    a = a.dup
    kw = a.pop
    assert_equal 'true', expr, insn, *a, **kw
  else
    assert_equal 'true', expr, insn, *a
  end
end

# with trace
tests.compact.each {|(insn, expr, *a)|
  progn = "set_trace_func(proc{})\n" + expr
  if a.last.is_a?(Hash)
    a = a.dup
    kw = a.pop
    assert_equal 'true', progn, 'trace_' + insn, *a, **kw
  else
    assert_equal 'true', progn, 'trace_' + insn, *a
  end
}

assert_normal_exit("#{<<-"begin;"}\n#{<<-'end;'}")
begin;
  RubyVM::InstructionSequence.compile("", debug_level: 5)
end;
