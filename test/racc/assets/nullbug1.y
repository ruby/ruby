#
# number of conflicts must be ZERO.
#

class T

rule

targ  : dummy
      | a b c

dummy : V v

V     : E e
      | F f
      |
      ;

E     :
      ;

F     :
      ;

end
