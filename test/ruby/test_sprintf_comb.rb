require 'test/unit'

class TestSprintfComb < Test::Unit::TestCase
  VS = [
    #-0x1000000000000000000000000000000000000000000000002,
    #-0x1000000000000000000000000000000000000000000000001,
    #-0x1000000000000000000000000000000000000000000000000,
    #-0xffffffffffffffffffffffffffffffffffffffffffffffff,
    #-0x1000000000000000000000002,
    #-0x1000000000000000000000001,
    #-0x1000000000000000000000000,
    #-0xffffffffffffffffffffffff,
    -0x10000000000000002,
    -0x10000000000000001,
    -0x10000000000000000,
    -0xffffffffffffffff,
    -0x4000000000000002,
    -0x4000000000000001,
    -0x4000000000000000,
    -0x3fffffffffffffff,
    -0x100000002,
    -0x100000001,
    -0x100000000,
    -0xffffffff,
    #-0xc717a08d, # 0xc717a08d * 0x524b2245 = 0x4000000000000001
    -0x80000002,
    -0x80000001,
    -0x80000000,
    -0x7fffffff,
    #-0x524b2245,
    -0x40000002,
    -0x40000001,
    -0x40000000,
    -0x3fffffff,
    #-0x10002,
    #-0x10001,
    #-0x10000,
    #-0xffff,
    #-0x8101, # 0x8101 * 0x7f01 = 0x40000001
    #-0x8002,
    #-0x8001,
    #-0x8000,
    #-0x7fff,
    #-0x7f01,
    #-65,
    #-64,
    #-63,
    #-62,
    #-33,
    #-32,
    #-31,
    #-30,
    -3,
    -2,
    -1,
    0,
    1,
    2,
    3,
    #30,
    #31,
    #32,
    #33,
    #62,
    #63,
    #64,
    #65,
    #0x7f01,
    #0x7ffe,
    #0x7fff,
    #0x8000,
    #0x8001,
    #0x8101,
    #0xfffe,
    #0xffff,
    #0x10000,
    #0x10001,
    0x3ffffffe,
    0x3fffffff,
    0x40000000,
    0x40000001,
    #0x524b2245,
    0x7ffffffe,
    0x7fffffff,
    0x80000000,
    0x80000001,
    #0xc717a08d,
    0xfffffffe,
    0xffffffff,
    0x100000000,
    0x100000001,
    0x3ffffffffffffffe,
    0x3fffffffffffffff,
    0x4000000000000000,
    0x4000000000000001,
    0xfffffffffffffffe,
    0xffffffffffffffff,
    0x10000000000000000,
    0x10000000000000001,
    #0xffffffffffffffffffffffff,
    #0x1000000000000000000000000,
    #0x1000000000000000000000001,
    #0xffffffffffffffffffffffffffffffffffffffffffffffff,
    #0x1000000000000000000000000000000000000000000000000,
    #0x1000000000000000000000000000000000000000000000001
  ]
  VS.reverse!

  def combination(*args)
    args = args.map {|a| a.to_a }
    i = 0
    while true
      n = i
      as = []
      args.reverse_each {|a|
        n, m = n.divmod(a.length)
        as.unshift a[m]
      }
      break if 0 < n
      yield as
      i += 1
    end
  end

  def emu(format, v)
    /\A%( )?(\#)?(\+)?(-)?(0)?(\d+)?(?:\.(\d+))?(.)\z/ =~ format
    sp = $1
    hs = $2
    pl = $3
    mi = $4
    zr = $5
    width = $6
    precision = $7
    type = $8
    width = width.to_i if width
    precision = precision.to_i if precision
    prefix = ''

    zr = nil if precision

    zr = nil if mi && zr

    case type
    when 'b'
      radix = 2
      digitmap = {0 => '0', 1 => '1'}
      complement = !pl && !sp
      prefix = '0b' if hs && v != 0
    when 'd'
      radix = 10
      digitmap = {}
      10.times {|i| digitmap[i] = i.to_s }
      complement = false
    when 'o'
      radix = 8
      digitmap = {}
      8.times {|i| digitmap[i] = i.to_s }
      complement = !pl && !sp
    when 'X'
      radix = 16
      digitmap = {}
      16.times {|i| digitmap[i] = i.to_s(16).upcase }
      complement = !pl && !sp
      prefix = '0X' if hs && v != 0
    when 'x'
      radix = 16
      digitmap = {}
      16.times {|i| digitmap[i] = i.to_s(16) }
      complement = !pl && !sp
      prefix = '0x' if hs && v != 0
    else
      raise "unexpected type: #{type.inspect}"
    end

    digits = []
    abs = v.abs
    sign = ''
    while 0 < abs
      digits << (abs % radix)
      abs /= radix
    end

    if v < 0
      if complement
        digits.map! {|d| radix-1 - d }
        carry = 1
        digits.each_index {|i|
          digits[i] += carry
          carry = 0
          if radix <= digits[i]
            digits[i] -= radix
            carry = 1
          end
        }
        if digits.last != radix-1
          digits << (radix-1)
        end
        sign = '..'
      else
        sign = '-'
      end
    else
      if pl
        sign = '+'
      elsif sp
        sign = ' '
      end
    end

    dlen = digits.length
    dlen += 2 if sign == '..'

    if v < 0 && complement
      d = radix - 1
    else
      d = 0
    end
    if precision
      if dlen < precision
        (precision - dlen).times {
          digits << d
        }
      end
    else
      if dlen == 0
        digits << d
      end
    end
    if type == 'o' && hs
      if digits.empty? || digits.last != d
        digits << d
      end
    end

    digits.reverse!

    str = digits.map {|d| digitmap[d] }.join

    pad = ''
    nlen = prefix.length + sign.length + str.length
    if width && nlen < width
      len = width - nlen
      if zr
        if complement && v < 0
          pad = digitmap[radix-1] * len
        else
          pad = '0' * len
        end
      else
        pad = ' ' * len
      end
    end

    if / / =~ pad
      if sign == '..'
        str = prefix + sign + str
      else
        str = sign + prefix + str
      end
      if mi
        str = str + pad
      else
        str = pad + str
      end
    else
      if sign == '..'
        str = prefix + sign + pad + str
      else
        str = sign + prefix + pad + str
      end
    end

    str
  end

  def test_format
    combination(
        %w[b d o X x],
        [nil, 0, 5, 20],
        [nil, 0, 8, 20],
        ['', ' '],
        ['', '#'],
        ['', '+'],
        ['', '-'],
        ['', '0']) {|type, width, precision, sp, hs, pl, mi, zr|
      if precision
        precision = ".#{precision}"
      end
      format = "%#{sp}#{hs}#{pl}#{mi}#{zr}#{width}#{precision}#{type}"
      VS.each {|v|
        r = sprintf format, v
        e = emu format, v
        if true
          assert_equal(e, r, "sprintf(#{format.dump}, #{v})")
        else
          if e != r
            puts "#{e.dump}\t#{r.dump}\tsprintf(#{format.dump}, #{v})"
          end
        end
      }
    }
  end
end
