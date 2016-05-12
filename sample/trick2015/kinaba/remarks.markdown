### Remarks

Just run it with no argument:

    $ ruby entry.rb

I confirmed the following implementation/platform:

- ruby 2.2.3p173 (2015-08-18 revision 51636) [x64-mingw32]


### Description

The program is a [Piphilology](https://en.wikipedia.org/wiki/Piphilology#Examples_in_English)
suitable for Rubyists to memorize the digits of [Pi](https://en.wikipedia.org/wiki/Pi).

In English, the poems for memorizing Pi start with a word consisting of 3-letters,
1-letter, 4-letters, 1-letter, 5-letters, ... and so on. 10-letter words are used for the
digit `0`. In Ruby, the lengths of the lexical tokens tell you the number.

    $ ruby -r ripper -e \
        'puts Ripper.tokenize(STDIN).grep(/\S/).map{|t|t.size%10}.join' < entry.rb
    31415926535897932384626433832795028841971693993751058209749445923078164062862...

The program also tells you the first 10000 digits of Pi, by running.

    $ ruby entry.rb
    31415926535897932384626433832795028841971693993751058209749445923078164062862...


### Internals

Random notes on what you might think interesting:

- The 10000 digits output of Pi is seriously computed with no cheets. It is calculated
  by the formula `Pi/2 = 1 + 1/3 + 1/3*2/5 + 1/3*2/5*3/7 + 1/3*2/5*3/7*4/9 + ...`.

- Lexical tokens are not just space-separated units. For instance, `a*b + cdef` does
  not represent [3,1,4]; rather it's [1,1,1,1,4]. The token length
  burden imposes hard constraints on what we can write.

- That said, Pi is [believed](https://en.wikipedia.org/wiki/Normal_number) to contain
  all digit sequences in it. If so, you can find any program inside Pi in theory.
  In practice it isn't that easy particularly under the TRICK's 4096-char
  limit rule. Suppose we want to embed `g += hij`. We have to find [1,2,3] from Pi.
  Assuming uniform distribution, it occurs once in 1000 digits, which already consumes
  5000 chars in average to reach the point. We need some TRICK.

  - `alias` of global variables was useful. It allows me to access the same value from
    different token-length positions.

  - `srand` was amazingly useful. Since it returns the "previous seed", the token-length
    `5` essentially becomes a value-store that can be written without waiting for the
    1-letter token `=`.

- Combination of these techniques leads to a carefully chosen 77-token Pi computation
  program (quoted below), which is embeddable to the first 242 tokens of Pi.
  Though the remaining 165 tokens are just no-op fillers, it's not so bad compared to
  the 1000/3 = 333x blowup mentioned above.


    big, temp = Array 100000000**0x04e2
    srand big
    alias $curTerm $initTerm
    big += big
    init ||= big
    $counter ||= 02
    while 0x00012345 >= $counter
      numbase = 0x0000
      $initTerm ||= Integer srand * 0x00000002
      srand $counter += 0x00000001
      $sigmaTerm ||= init
      $curTerm /= srand
      pi, = Integer $sigmaTerm
      $counter += 1
      srand +big && $counter >> 0b1
      num = numbase |= srand
      $sigmaTerm += $curTerm
      pi += 3_3_1_3_8
      $curTerm *= num
    end
    print pi

- By the way, what's the blowup ratio of the final code, then?
  It's 242/77, whose first three digits are, of course, 3.14.
