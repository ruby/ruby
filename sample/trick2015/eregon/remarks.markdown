### Remarks

Just run it without arguments:

    ruby entry.rb

I confirmed the following implementations and platforms:

* Linux:
  * ruby 2.3.0dev (2015-10-30 trunk 52394) [x86\_64-linux]
  * ruby 2.2.2p95 (2015-04-13 revision 50295) [x86\_64-linux]
  * ruby 2.0.0p647 (2015-08-18) [x86\_64-linux]
* Darwin:
  * ruby 2.0.0p247 (2013-06-27 revision 41674) [x86\_64-darwin10.8.0]
  * jruby 9.0.3.0 (2.2.2) 2015-10-21 633c9aa Java HotSpot(TM) 64-Bit Server VM 25.11-b03 on 1.8.0\_11-b12 +jit [darwin-x86\_64]
  * rubinius 2.2.6.n74 (2.1.0 94b3a9b4 2014-03-15 JI) [x86\_64-darwin12.5.0]

### Description

This program shows all solutions of any sudoku puzzle.

The embedded sudoku puzzle can be changed at wish.

Giving an empty puzzle (all `0` or `_`), the program will print every possible completed sudoku puzzle.
We do not however make any time guarantee on such behavior.

The program is rather small for the task: the solver is actually 302 characters long,  
assuming the sudoku puzzle is in a variable `s` and encoded as an array of rows of numbers.

### Internals

* The program implements backtracking and keeps state in a very elegant way.
* The whole program never goes deeper than 9 stack frames,
  but yet can backtrack up to 81 levels!
* The main loop of a program is a dance between cells.
  On one end is the solutions, on the other the program ends.
* The program only uses *infinite* loops and no `break`.
* The program interleaves the creation of the solver and the puzzle.
* The program is easy to deobfuscate but finding how it works will be more challenging.
* The last line contains a smiley.

The author likes good numbers:

    $ wc entry.rb
          15      42     600

The inspiration for this entry comes from:

* A newspaper sudoku with multiple solutions
* An inspiring paper: `Revisiting Coroutines`

Various tricks used for brevity:

* The method defined is one of the fews which may contain neither parenthesis nor spaces.
* The program uses the return value of Fiber.yield without arguments.
* `String#b` is used as a very short `self`.

Design issues:

* Since `return`-ing from a Fiber is not allowed, the programs must `exit`.
* The program reveals that the cartesian product operator is still too long: `a.product(a)` while it could be `a*a`.

Note:

* In the original code, the last cell was: `C.new{loop{yield s; C.yield}}`,
  implementing some sort of "forwarding coroutine".

### Limitation

* The program does not want any *argument* with you and will quit quietly if you try some.
