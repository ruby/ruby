foo = Struct.new("test", "a1"::1, "a2"::2)
print(foo, "\n")
bar = foo.clone
print(bar.a1, "\n")
