# 1 s/r conflict and 1 r/r conflict

class A
rule

target: a

a     :
      | a list

list  :
      | list ITEM

end
