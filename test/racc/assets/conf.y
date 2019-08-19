
class A
rule

a: A c C expr;

b: A B;  # useless

c: A;
c: A;

expr: expr '+' expr
expr: expr '-' expr
expr: NUMBER

end
