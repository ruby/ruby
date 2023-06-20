[*a]

foo[bar, baz] = 1, 2, 3

[a: [:b, :c]]



[:a, :b,
:c,1,



:d,
]


[:a, :b,
:c,1,



:d


]

[foo => bar]

foo[bar][baz] = qux

foo[bar][baz]

[
]

foo[bar, baz]

foo[bar, baz] = qux

foo[0], bar[0] = 1, 2

foo[bar[baz] = qux]

foo[bar]

foo[bar] = baz

[**{}]

[**kw]

[1, **kw]

[1, **kw, **{}, **kw]

[
  foo => bar,
]


%i#one two three#

%w#one two three#

%x#one two three#


%i@one two three@

%w@one two three@

%x@one two three@


%i{one two three}

%w{one two three}

%x{one two three}
