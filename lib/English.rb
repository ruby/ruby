# frozen_string_literal: true
#  Include the English library file in a Ruby script, and you can
#  reference the global variables such as \VAR{\$\_} using less
#  cryptic names, listed below.
#
#  Without 'English':
#
#      $\ = ' -- '
#      "waterbuffalo" =~ /buff/
#      print $', $$, "\n"
#
#  With English:
#
#      require "English"
#
#      $OUTPUT_FIELD_SEPARATOR = ' -- '
#      "waterbuffalo" =~ /buff/
#      print $POSTMATCH, $PID, "\n"
#
#  Below is a full list of descriptive aliases and their associated global
#  variable:
#
#  $ERROR_INFO::              $!
#  $ERROR_POSITION::          $@
#  $FS::                      $;
#  $FIELD_SEPARATOR::         $;
#  $OFS::                     $,
#  $OUTPUT_FIELD_SEPARATOR::  $,
#  $RS::                      $/
#  $INPUT_RECORD_SEPARATOR::  $/
#  $ORS::                     $\
#  $OUTPUT_RECORD_SEPARATOR:: $\
#  $INPUT_LINE_NUMBER::       $.
#  $NR::                      $.
#  $LAST_READ_LINE::          $_
#  $DEFAULT_OUTPUT::          $>
#  $DEFAULT_INPUT::           $<
#  $PID::                     $$
#  $PROCESS_ID::              $$
#  $CHILD_STATUS::            $?
#  $LAST_MATCH_INFO::         $~
#  $IGNORECASE::              $=
#  $ARGV::                    $*
#  $MATCH::                   $&
#  $PREMATCH::                $`
#  $POSTMATCH::               $'
#  $LAST_PAREN_MATCH::        $+
#
module English end if false

# The exception object passed to +raise+.
alias $ERROR_INFO              $!

# The stack backtrace generated by the last
# exception. <tt>See Kernel.caller</tt> for details. Thread local.
alias $ERROR_POSITION          $@

# The default separator pattern used by <tt>String.split</tt>.  May be
# set from the command line using the <tt>-F</tt> flag.
alias $FS                      $;

# The default separator pattern used by <tt>String.split</tt>.  May be
# set from the command line using the <tt>-F</tt> flag.
alias $FIELD_SEPARATOR         $;

# The separator string output between the parameters to methods such
# as <tt>Kernel.print</tt> and <tt>Array.join</tt>. Defaults to +nil+,
# which adds no text.
alias $OFS                     $,

# The separator string output between the parameters to methods such
# as <tt>Kernel.print</tt> and <tt>Array.join</tt>. Defaults to +nil+,
# which adds no text.
alias $OUTPUT_FIELD_SEPARATOR  $,

# The input record separator (newline by default). This is the value
# that routines such as <tt>Kernel.gets</tt> use to determine record
# boundaries. If set to +nil+, +gets+ will read the entire file.
alias $RS                      $/

# The input record separator (newline by default). This is the value
# that routines such as <tt>Kernel.gets</tt> use to determine record
# boundaries. If set to +nil+, +gets+ will read the entire file.
alias $INPUT_RECORD_SEPARATOR  $/

# The string appended to the output of every call to methods such as
# <tt>Kernel.print</tt> and <tt>IO.write</tt>. The default value is
# +nil+.
alias $ORS                     $\

# The string appended to the output of every call to methods such as
# <tt>Kernel.print</tt> and <tt>IO.write</tt>. The default value is
# +nil+.
alias $OUTPUT_RECORD_SEPARATOR $\

# The number of the last line read from the current input file.
alias $INPUT_LINE_NUMBER       $.

# The number of the last line read from the current input file.
alias $NR                      $.

# The last line read by <tt>Kernel.gets</tt> or
# <tt>Kernel.readline</tt>. Many string-related functions in the
# +Kernel+ module operate on <tt>$_</tt> by default. The variable is
# local to the current scope. Thread local.
alias $LAST_READ_LINE          $_

# The destination of output for <tt>Kernel.print</tt>
# and <tt>Kernel.printf</tt>. The default value is
# <tt>$stdout</tt>.
alias $DEFAULT_OUTPUT          $>

# An object that provides access to the concatenation
# of the contents of all the files
# given as command-line arguments, or <tt>$stdin</tt>
# (in the case where there are no
# arguments). <tt>$<</tt> supports methods similar to a
# +File+ object:
# +inmode+, +close+,
# <tt>closed?</tt>, +each+,
# <tt>each_byte</tt>, <tt>each_line</tt>,
# +eof+, <tt>eof?</tt>, +file+,
# +filename+, +fileno+,
# +getc+, +gets+, +lineno+,
# <tt>lineno=</tt>, +path+,
# +pos+, <tt>pos=</tt>,
# +read+, +readchar+,
# +readline+, +readlines+,
# +rewind+, +seek+, +skip+,
# +tell+, <tt>to_a</tt>, <tt>to_i</tt>,
# <tt>to_io</tt>, <tt>to_s</tt>, along with the
# methods in +Enumerable+. The method +file+
# returns a +File+ object for the file currently
# being read. This may change as <tt>$<</tt> reads
# through the files on the command line. Read only.
alias $DEFAULT_INPUT           $<

# The process number of the program being executed. Read only.
alias $PID                     $$

# The process number of the program being executed. Read only.
alias $PROCESS_ID              $$

# The exit status of the last child process to terminate. Read
# only. Thread local.
alias $CHILD_STATUS            $?

# A +MatchData+ object that encapsulates the results of a successful
# pattern match. The variables <tt>$&</tt>, <tt>$`</tt>, <tt>$'</tt>,
# and <tt>$1</tt> to <tt>$9</tt> are all derived from
# <tt>$~</tt>. Assigning to <tt>$~</tt> changes the values of these
# derived variables.  This variable is local to the current
# scope.
alias $LAST_MATCH_INFO         $~

# This variable is no longer effective. Deprecated.
alias $IGNORECASE              $=

# An array of strings containing the command-line
# options from the invocation of the program. Options
# used by the Ruby interpreter will have been
# removed. Read only. Also known simply as +ARGV+.
alias $ARGV                    $*

# The string matched by the last successful pattern
# match. This variable is local to the current
# scope. Read only.
alias $MATCH                   $&

# The string preceding the match in the last
# successful pattern match. This variable is local to
# the current scope. Read only.
alias $PREMATCH                $`

# The string following the match in the last
# successful pattern match. This variable is local to
# the current scope. Read only.
alias $POSTMATCH               $'

# The contents of the highest-numbered group matched in the last
# successful pattern match. Thus, in <tt>"cat" =~ /(c|a)(t|z)/</tt>,
# <tt>$+</tt> will be set to "t".  This variable is local to the
# current scope. Read only.
alias $LAST_PAREN_MATCH        $+
