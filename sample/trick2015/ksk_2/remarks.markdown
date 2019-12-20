### Remarks

The program is run with a data file from the standard input, e.g.,
```shell
  ruby entry.rb < data
```
where ``<`` can be omitted.  The data file must be in the DIMACS CNF
format (see Description for detail).  It has been confirmed to be run on
```
  ruby 1.9.3p385 (2013-02-06 revision 39114) [x86_64-darwin11.4.2]
  ruby 2.0.0p481 (2014-05-08 revision 45883) [universal.x86_64-darwin13]
  ruby 2.2.3p173 (2015-08-18 revision 51636) [x86_64-linux]
```
For particular inputs, the program works differently on these environments
(see Limitation).


### Description

The program is a very small SAT solver with 194 bytes making use of a
powerful feature of Regexp matching in Ruby.  It receives a data file
from the standard input in the DIMACS CNF that is a standard format
for inputs of SAT solvers.  For example, the text in the DIMACS CNF
format,
```
c
c This is a sample input file.
c
p cnf 3 5
 1 -2  3 0
-1  2 0
-2 -3 0
 1  2 -3 0
 1  3 0
```
corresponds to a propositional formula in conjunctive normal form,

  (L1      &or; &not;L2 &or; L3) &and;
  (&not;L1 &or;      L2) &and;
  (&not;L2 &or; &not;L3) &and;
  (L1      &or; L2      &or; &not;L3) &and;
  (L1      &or; L3).

In the DIMACS CNF format, the lines starting with ``c`` are comments
that are allowed only before the line ``p cnf ...``.  The line ``p cnf
3 5`` represents that the problem is given in conjunctive normal form
with 3 variables (L1,L2,and L3) and 5 clauses.  A clause is given by a
sequence of the indices of positive literals and the negative indices
of negative literals.  Each clause is terminated by ``0``.  For the
input above, the program outputs
```
s SATISFIABLE
v 1 2 -3
```
because the formula is satisfiable by L1=true, L2=true, and L3=false.
If an unsatisfiable formula is given, the program should output
```
s UNSATISFIABLE
```
This specification is common in most exiting SAT solvers and required
for entries of [SAT competition](http://www.satcompetition.org/).

The program is very small with no other external libraries thanks to
the wealth of string manipulations in Ruby.  It is much smaller than
existing small SAT solvers like [minisat](http://minisat.se/) and
[picosat](http://fmv.jku.at/picosat/)!


### Internals

The basic idea of the program is a translation from DIMACS CNF format
into Ruby.  For example, the data file above is translated into a
``Regexp`` matching expression equivalent to
```ruby
 '---=-' =~ 
 /(-?)(-?)(-?)-*=(?=\1$|-\2$|\3$|$)(?=-\1$|\2$|$)(?=-\2$|-\3$|$)(?=\1$|\2$|-\3$|$)(?=\1$|\3$|$)(?=)/
```
that returns ``MatchData`` if the formula is satisfiable and otherwise
returns ``nil``.  The beginning of regular expression
``(-?)(-?)(-?)-*=`` matches a string ``"---="`` so that each
capturing pattern ``(-?)`` matches either ``"-"`` or `""`, which
corresponds to an assignment of true or false, respectively, for a
propositional variable.  Each clause is translated into positive
lookahead assertion like ``(?=\1$|-\2$|\3$|$)`` that matches 
``"-"`` only when ``\1`` holds ``"-"``, ``\2`` holds ``""``, or ``\3``
holds ``"-"``.  This exactly corresponds to the condition for
L1&or;&not;L2&or;L3 to be true.  The last case ``|$`` never matches
``"-"`` but it is required for making the translation simple.
The last meaningless positive lookahead assertion ``(?=)`` is added
for a similar reason.  This translation is based on
[Abigail's idea](http://perl.plover.com/NPC/NPC-3SAT.html) where a
3SAT formula is translated into a similar Perl regular expression.
The differences are the submitted Ruby program translates directly
from the DIMACS CNF format and tries to make the code shorter by using
lookahead assertion which can also make matching more faster.

Thanks to the ``x`` option for regular expression, the input above is
simply translated into
```ruby
  ?-*3+'=-'=~/#{'(-?)'*3}-*=(?=
   \1$| -\2$|  \3$| $)(?=
  -\1$|  \2$| $)(?=
  -\2$| -\3$| $)(?=
   \1$|  \2$| -\3$| $)(?=
   \1$|  \3$| $)(?=
  )/x
```
which has a structure similar to the DIMACS CNF format.

The part of formatting outputs in the program is obfuscated as an
inevitable result of 'golfing' the original program
```ruby
   if ...the matching expression above... then
     puts 's SATISFIABLE'
     puts 'v '+$~[1..-1].map.with_index{|x,i|
       if x == '-' then
         i+1
       else
         ['-',i+1].join
       end
     }.join(' ')
   else
     puts 's UNSATISFIABLE'
   end
```
In the satisfiable case, the MatchData ``$~`` obtained by the regular expression
has the form of
```
  #<MatchData "---=" 1:"-" 2:"-" 3:"">
```
which should be translated into a string ``1 2 -3``.  The golfed code simply
does it by `eval(x+?1)*i-=1` where ``x`` is matched string ``"x"`` or ``""``
and ``i`` be a negated index.


### Data files

The submission includes some input files in the DIMACS CNF format for
testing the program.

* [sample.cnf](sample.cnf) : an example shown above.

* [unsat.cnf](unsat.cnf) : an example of an unsatisfiable formula.

* [quinn.cnf](quinn.cnf) : an example from Quinn's text, 16 variables and 18 clauses
   (available from [http://people.sc.fsu.edu/~jburkardt/data/cnf/cnf.html])

* [abnormal.cnf](abnormal.cnf) : an example from [the unofficial manual of the DIMACS challenge](http://www.domagoj-babic.com/uploads/ResearchProjects/Spear/dimacs-cnf.pdf)
  where a single clause may be on multiple lines.

* [uf20-01.cnf](uf20-01.cnf) : an example, with 20 variables and 91 clauses, from [SATLIB benchmark suite](http://www.cs.ubc.ca/~hoos/SATLIB/benchm.html).  The last two lines are removed from the original because they are illegal in the DIMACS CNF format (all examples in 'Uniform Random-3-SAT' of the linked page need this modification).


### Limitation

The program may not work when the number of variables exceeds 99
because ``\nnn`` in regular expression with number ``nnn`` does not
always represent backreference but octal notation of characters.  For
example,
```ruby
  /#{"(x)"*999}:\502/=~"x"*999+":x"
  /#{"(x)"*999}:\661/=~"x"*999+":x"
  /#{"(x)"*999}:\775/=~"x"*999+":x"
```
fail due to the syntax error (invalid escape), while
```ruby
  /#{"(x)"*999}:\508/=~"x"*999+":x"
  /#{"(x)"*999}:\691/=~"x"*999+":x"
  /#{"(x)"*999}:\785/=~"x"*999+":x"
```
succeed (to return 0) because 508, 691, and 785 are not in octal notation.
Since Ruby 1.9.3 incorrectly returns ``nil`` instead of terminating
with the error for
```ruby
  /#{"(x)"*999}:\201/=~"x"*999+":x"
  /#{"(x)"*999}:\325/=~"x"*999+":x"
```
the present SAT solver may unexpectedly return "UNSATISFIABLE" even
for satisfiable inputs.  This happens when the number is in octal
notation starting with either 2 or 3.

In the case of the number starting with 1, the code like the above
does work on all versions of Ruby I tried.  For example,
```ruby
  /#{"(x)"*999}:\101/=~"x"*999+":x"
  /#{"(x)"*999}:\177/=~"x"*999+":x"
```
succeed (to return 0).  Interestingly, 
```ruby
  /#{"(x)"*999}:\101/=~"x"*999+":\101"
  /#{"(x)"*999}:\177/=~"x"*999+":\177"
```
return ``nil``, while
```ruby
  /:\101/=~":\101"
  /:\177/=~":\177"
```
succeed to return 0.  The meaning of ``\1nn`` in regular expression
seems to depend on the existence of capturing expressions.

In spite of these Ruby's behaviors, we have a good news!  The present
SAT solver does not suffer from the issues because the program cannot
return solutions in practical time for inputs with variables more than
40.
