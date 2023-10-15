foo[bar] { baz }

foo[bar] do
baz
end

x.reduce(0) { |x, memo| memo += x }

foo do end

foo bar, (baz do end)

foo bar do end

foo bar baz do end

foo do |a = b[1]|
end

foo do
rescue
end

foo do
  bar do
    baz do
    end
  end
end

foo[bar] { baz }

foo { |x, y = 2, z:| x }

foo { |x| }

fork = 1
fork do |a|
end

fork { |a| }

C do
end

C {}

foo lambda { |
  a: 1,
  b: 2
  |
}

foo do |bar,| end
