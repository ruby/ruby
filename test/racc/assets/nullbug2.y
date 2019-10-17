#
# number of conflicts must be ZERO.
#

class A
rule
  targ: operation voidhead
      | variable

  voidhead : void B
  void:

  operation: A
  variable : A
end
