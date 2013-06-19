value = 0.01
h = {}
n = 100_000

1.upto(n){|i|
  h["%020d" % i] = value * i
}

(n * 500).times{
  ''
}
