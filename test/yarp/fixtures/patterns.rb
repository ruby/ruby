foo => bar
foo => 1
foo => 1.0
foo => 1i
foo => 1r
foo => :foo
foo => %s[foo]
foo => :"foo"
foo => /foo/
foo => `foo`
foo => %x[foo]
foo => %i[foo]
foo => %I[foo]
foo => %w[foo]
foo => %W[foo]
foo => %q[foo]
foo => %Q[foo]
foo => "foo"
foo => nil
foo => self
foo => true
foo => false
foo => __FILE__
foo => __LINE__
foo => __ENCODING__
foo => -> { bar }

foo => 1 .. 1
foo => 1.0 .. 1.0
foo => 1i .. 1i
foo => 1r .. 1r
foo => :foo .. :foo
foo => %s[foo] .. %s[foo]
foo => :"foo" .. :"foo"
foo => /foo/ .. /foo/
foo => `foo` .. `foo`
foo => %x[foo] .. %x[foo]
foo => %i[foo] .. %i[foo]
foo => %I[foo] .. %I[foo]
foo => %w[foo] .. %w[foo]
foo => %W[foo] .. %W[foo]
foo => %q[foo] .. %q[foo]
foo => %Q[foo] .. %Q[foo]
foo => "foo" .. "foo"
foo => nil .. nil
foo => self .. self
foo => true .. true
foo => false .. false
foo => __FILE__ .. __FILE__
foo => __LINE__ .. __LINE__
foo => __ENCODING__ .. __ENCODING__
foo => -> { bar } .. -> { bar }

foo => ^bar
foo => ^@bar
foo => ^@@bar
foo => ^$bar

foo => ^(1)
foo => ^(nil)
foo => ^("bar" + "baz")

foo => Foo
foo => Foo::Bar::Baz
foo => ::Foo
foo => ::Foo::Bar::Baz

foo => Foo()
foo => Foo(1)
foo => Foo(1, 2, 3)
foo => Foo(bar)
foo => Foo(*bar, baz)
foo => Foo(bar, *baz)
foo => Foo(*bar, baz, *qux)

foo => Foo[]
foo => Foo[1]
foo => Foo[1, 2, 3]
foo => Foo[bar]
foo => Foo[*bar, baz]
foo => Foo[bar, *baz]
foo => Foo[*bar, baz, *qux]

foo => *bar
foo => *bar, baz, qux
foo => bar, *baz, qux
foo => bar, baz, *qux
foo => *bar, baz, *qux

foo => []
foo => [[[[[]]]]]

foo => [*bar]
foo => [*bar, baz, qux]
foo => [bar, *baz, qux]
foo => [bar, baz, *qux]
foo => [*bar, baz, *qux]

foo in bar
foo in 1
foo in 1.0
foo in 1i
foo in 1r
foo in :foo
foo in %s[foo]
foo in :"foo"
foo in /foo/
foo in `foo`
foo in %x[foo]
foo in %i[foo]
foo in %I[foo]
foo in %w[foo]
foo in %W[foo]
foo in %q[foo]
foo in %Q[foo]
foo in "foo"
foo in nil
foo in self
foo in true
foo in false
foo in __FILE__
foo in __LINE__
foo in __ENCODING__
foo in -> { bar }

case foo; in bar then end
case foo; in 1 then end
case foo; in 1.0 then end
case foo; in 1i then end
case foo; in 1r then end
case foo; in :foo then end
case foo; in %s[foo] then end
case foo; in :"foo" then end
case foo; in /foo/ then end
case foo; in `foo` then end
case foo; in %x[foo] then end
case foo; in %i[foo] then end
case foo; in %I[foo] then end
case foo; in %w[foo] then end
case foo; in %W[foo] then end
case foo; in %q[foo] then end
case foo; in %Q[foo] then end
case foo; in "foo" then end
case foo; in nil then end
case foo; in self then end
case foo; in true then end
case foo; in false then end
case foo; in __FILE__ then end
case foo; in __LINE__ then end
case foo; in __ENCODING__ then end
case foo; in -> { bar } then end

case foo; in bar if baz then end
case foo; in 1 if baz then end
case foo; in 1.0 if baz then end
case foo; in 1i if baz then end
case foo; in 1r if baz then end
case foo; in :foo if baz then end
case foo; in %s[foo] if baz then end
case foo; in :"foo" if baz then end
case foo; in /foo/ if baz then end
case foo; in `foo` if baz then end
case foo; in %x[foo] if baz then end
case foo; in %i[foo] if baz then end
case foo; in %I[foo] if baz then end
case foo; in %w[foo] if baz then end
case foo; in %W[foo] if baz then end
case foo; in %q[foo] if baz then end
case foo; in %Q[foo] if baz then end
case foo; in "foo" if baz then end
case foo; in nil if baz then end
case foo; in self if baz then end
case foo; in true if baz then end
case foo; in false if baz then end
case foo; in __FILE__ if baz then end
case foo; in __LINE__ if baz then end
case foo; in __ENCODING__ if baz then end
case foo; in -> { bar } if baz then end

if a in []
end

a => [
  b
]

foo in A[
  bar: B[
    value: a
  ]
]
