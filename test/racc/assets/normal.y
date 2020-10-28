
class Testp

  convert
    A '2'
    B '3'
  end

  prechigh
    left B
  preclow

rule

/* comment */
  target: A B C nonterminal { action "string" == /regexp/o
                              1 /= 3 }
        ;   # comment

  nonterminal: A '+' B  = A;

/* end */
end

---- driver

  # driver is old name
