$a = 1
($a, $b) = [1, 2]
((a,), b) = 1
(*a) = []
(*foo) = [1, 2]
(@@a, @@b) = [1, 2]
(@a, @b) = [1, 2]
(a, (b, c)) = [1, [2, 3]]
(a, *) = [1, 2]
(a, *foo) = [1, 2]
(a, b) = [1, 2]
(a, b) = foo
(a,) = foo
(a.foo, a.bar) = [1, 2]
(a[*foo], a[1]) = [1, 2]
(a[0], a[1]) = [1, 2]
(*c.foo) = 1
::Foo = ::Bar
@@a = 1
@a = 1
CONST = 1
Name::Spaced::CONST = 1
a = ((b, c) = 1)
a = 1
foo = foo()
foo.[]=()
foo.[]=(1, 2)
foo.[]=true
foo[*index] = value
foo[1..2] = value
foo[] = 1
foo[a, b] = value
foo[index] = value
x = %()
x.x=%()
x[%()] = bar
a[%()] ||= bar
@a ||= %()
x = <<-HEREDOC
  #{}
HEREDOC
x.x=<<-HEREDOC
  #{}
HEREDOC
x[] = <<-HEREDOC
  #{}
HEREDOC
a[<<-HEREDOC] ||= bar
  #{}
HEREDOC
@a ||= <<-HEREDOC
  #{}
HEREDOC
