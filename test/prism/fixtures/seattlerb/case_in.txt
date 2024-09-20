case :a
in  "b": 
end

case :a
in %I[a b]
end

case :a
in %W[a b]
end

case :a
in %i[a b]
end

case :a
in %w[a b]
end

case :a
in (...10)
end

case :a
in (..10)
end

case :a
in (1...)
end

case :a
in (1...3)
end

case :a
in (42)
end

case :a
in **nil
end

case :a
in /regexp/
end

case :a
in :b, *_, :c
end

case :a
in :b, [:c]
end

case :a
in Symbol()
end

case :a
in Symbol(*lhs, x, *rhs)
end

case :a
in Symbol[*lhs, x, *rhs]
end

case :a
in [->(b) { true }, c]
end

case :a
in [:a, b, c, [:d, *e, nil]]
end

case :a
in [A, *, B]
end

case :a
in [[:b, c], [:d, ^e]]
end

case :a
in []
end

case :a
in [^(a)]
end

case :a
in [^@a, ^$b, ^@@c]
end

case :a
in `echo hi`
end

case :a
in nil, nil, nil
end

case :a
in { "b": }
end

case :a
in {}
end
