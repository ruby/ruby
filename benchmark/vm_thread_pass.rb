# Plenty Thread.pass
# A performance may depend on GVL implementation.

tmax = (ARGV.shift || 8).to_i
lmax = 400_000 / tmax

(1..tmax).map{
  Thread.new{
    lmax.times{
      Thread.pass
    }
  }
}.each{|t| t.join}


