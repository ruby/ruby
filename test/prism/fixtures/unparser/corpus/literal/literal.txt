{ "foo" => <<-HEREDOC, "bar" => :baz }
  #{}
HEREDOC
{ "foo" => %(), "bar" => :baz }
["foo", %()]
a(<<-HEREDOC).a
  #{}
HEREDOC
a(%()).a
{ "foo" => <<-HEREDOC, **baz }
  #{}
HEREDOC
{ "foo" => %(), **baz }
"#@a #@@a #$a"
0
++1
1
1
1r
1.5r
1.3r
5i
-5i
0.6i
-0.6i
1000000000000000000000000000000i
1ri
"foo" "bar"
"foobar #{baz}"
"foo#{1}bar"
"\\\\#{}"
"#{}\#{}"
"\#{}#{}"
"foo\\\#{@bar}"
"\""
"foo bar"
"foo\nbar"
`foo`
`foo#{@bar}`
`)`
`\``
`"`
:foo
:"A B"
:foo
:"A B"
:"A\"B"
:""
/foo/
/[^-+',.\/:@[:alnum:]\[\]]+/
/foo#{@bar}/
/foo#{@bar}/imx
/#{"\u0000"}/
/\n/
/\n/
/\n/x
/\/\//x
:"foo#{bar}baz"
:"#{"foo"}"
(0.0 / 0.0)..1
1..(0.0 / 0.0)
(0.0 / 0.0)..100
-0.1
0.1
[1, 2]
[1, (), n2]
[1]
[]
[1, *@foo]
[*@foo, 1]
[*@foo, *@baz]
{}
{ () => () }
{ 1 => 2 }
{ 1 => 2, 3 => 4 }
{ a: (1 rescue foo), b: 2 }
{ a: 1, b: 2 }
{ a: :a }
{ :"a b" => 1 }
{ :-@ => 1 }
"#{}
#{}\na"
foo {
  "#{}
#{}\na"
}
:"a\\
b"
`  x
#{foo}
#`
