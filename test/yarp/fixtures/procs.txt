-> (a; b, c, d) { b }

-> do
ensure
end

-> do
rescue
else
ensure
end

-> { foo }

-> do; foo; end

-> a, b = 1, c:, d:, &e { a }

-> (a, b = 1, *c, d:, e:, **f, &g) { a }

-> (a, b = 1, *c, d:, e:, **f, &g) do
  a
end

-> (a) { -> b { a * b } }

-> ((a, b), *c) { }
