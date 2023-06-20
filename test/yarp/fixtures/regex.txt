foo /bar/

%r{abc}i

/a\b/

/aaa #$bbb/

/aaa #{bbb} ccc/

[/(?<foo>bar)/ =~ baz, foo]

/abc/i

%r/[a-z$._?][\w$.?#@~]*:/i

%r/([a-z$._?][\w$.?#@~]*)(\s+)(equ)/i

%r/[a-z$._?][\w$.?#@~]*/i

%r(
(?:[\w#$%_']|\(\)|\(,\)|\[\]|[0-9])*
  (?:[\w#$%_']+)
)

/(?#\))/ =~ "hi"

%r#pound#
