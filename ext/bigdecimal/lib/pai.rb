#!/usr/local/bin/ruby

#
# pai.rb
#

require "bigdecimal"
#
# Calculates 3.1415.... using J. Machin's formula.
#
def pai(sig) # sig: Number of significant figures
  exp    = -sig
  pi     = BigDecimal::new("0")
  two    = BigDecimal::new("2")
  m25    = BigDecimal::new("-0.04")
  m57121 = BigDecimal::new("-57121")

  u = BigDecimal::new("1")
  k = BigDecimal::new("1")
  w = BigDecimal::new("1")
  t = BigDecimal::new("-80")
  while (u.exponent >= exp) 
    t   = t*m25
    u,r = t.div(k,sig)
    pi  = pi + u
    k   = k+two
  end

  u = BigDecimal::new("1")
  k = BigDecimal::new("1")
  w = BigDecimal::new("1")
  t = BigDecimal::new("956")
  while (u.exponent >= exp )
    t,r = t.div(m57121,sig)
    u,r = t.div(k,sig)
    pi  = pi + u
    k   = k+two
  end
  pi
end

if $0 == __FILE__
  if ARGV.size == 1
    print "PAI("+ARGV[0]+"):\n"
    p pai(ARGV[0].to_i)
  else
    print "TRY: ruby pai.rb 1000 \n"
  end
end
