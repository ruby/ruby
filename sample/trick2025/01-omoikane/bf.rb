#!/usr/bin/ruby -w
# Simple BF interpretor.
#
# This works by translating input code into ruby and evaluating the
# translated ruby code.  Doing it this way runs much faster than
# interpreting BF on our own.
#
# There is no error reporting whatsoever.  A malformed input may result in
# a syntax error at run time, but good luck in finding where it came from.


# Setup empty tape and initial pointer position.  Note that tape size is
# fixed.  We can make it infinite by initializing it to "[]" here and
# adding some nil checks in the generated code, but avoiding those checks
# makes the program run ~10% faster.
$code = "t=Array.new(30000,0); p=0;"

# Counters for pending add or shift operations.  We buffer incoming +-<>
# operators and output a single merged operation when we encounter a
# different operator.
$buffered_add = 0
$buffered_shift = 0

# Flush pending add operations, if any.
def flush_add
   if $buffered_add != 0
      $code += "t[p]+=#{$buffered_add};"
      $buffered_add = 0
   end
end

# Flush pending shift operations, if any.
def flush_shift
   if $buffered_shift != 0
      $code += "p+=#{$buffered_shift};"
      $buffered_shift = 0
   end
end

def flush_pending_ops
   flush_add
   flush_shift
end

# Convert input characters to ruby.
ARGF.each_char{|c|
   case c
   when '+'
      flush_shift
      $buffered_add += 1
   when '-'
      flush_shift
      $buffered_add -= 1
   when '<'
      flush_add
      $buffered_shift -= 1
   when '>'
      flush_add
      $buffered_shift += 1
   when ','
      flush_pending_ops
      $code += "if c=STDIN.getc;" +
               "t[p]=c.ord;" +
               "else;" +
               "t[p]=-1;" +  # EOF is interpreted as -1.
               "end;"
   when '.'
      flush_pending_ops
      $code += "print t[p].chr;"
   when '['
      flush_pending_ops
      $code += "while t[p]!=0;"
   when ']'
      flush_pending_ops
      $code += "end;"
   end
}
flush_pending_ops

# Evaluate converted code.
eval $code
