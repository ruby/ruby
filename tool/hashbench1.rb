value = 0.01
h = {}
n = 50_000

1.upto(n){|i|
  h["%020d" % i] = "v-#{i}"
}

(n * 1_000).times{
  ''
}
