#
#		getopts.rb - 
#			$Release Version: $
#			$Revision$
#			$Date$
#			by Yasuo OHBA(SHL Japan Inc. Technology Dept.)
#
# --
#
#	
#

$RCS_ID=%q$Header$

def isSingle(lopt)
  if lopt.index(":")
    if lopt.split(":")[0].length == 1
      return true
    end
  end
  return nil
end

def getOptionName(lopt)
  return lopt.split(":")[0]
end

def getDefaultOption(lopt)
  od = lopt.split(":")[1]
  if od
    return od
  end
  return nil
end

def setOption(name, value)
  eval("$OPT_" + name + " = " + 'value')
end

def setDefaultOption(lopt)
  d = getDefaultOption(lopt)
  if d
    setOption(getOptionName(lopt), d)
  end
end

def setNewArgv(newargv)
  ARGV.clear
  for na in newargv
    ARGV << na
  end
end


def getopts(single_opts, *options)
  if options
    single_colon = ""
    long_opts = []
    sc = 0
    for o in options
      setDefaultOption(o)
      if isSingle(o)
	single_colon[sc, 0] = getOptionName(o)
	sc += 1
      else
	long_opts.push(o)
      end
    end
  end
  
  opts = {}
  count = 0
  newargv = []
  while ARGV.length != 0
    compare = nil
    case ARGV[0]
    when /^--?$/
      ARGV.shift
      newargv += ARGV
      break
    when /^--.*/
      compare = ARGV[0][2, (ARGV[0].length - 2)]
      if long_opts != ""
	for lo in long_opts
	  if lo.index(":") && getOptionName(lo) == compare
	    if ARGV.length <= 1
	      return nil
	    end
	    setOption(compare, ARGV[1])
	    opts[compare] = true
	    ARGV.shift
	    count += 1
	    break
	  elsif lo == compare
	    setOption(compare, true)
	    opts[compare] = true
	    count += 1
	    break
	  end
	end
      end
      if compare.length <= 1
	return nil
      end
    when /^-.*/
      for idx in 1..(ARGV[0].length - 1)
	compare = ARGV[0][idx, 1]
	if single_opts && compare =~ "[" + single_opts + "]"
	  setOption(compare, true)
	  opts[compare] = true
	  count += 1
	elsif single_colon != "" && compare =~ "[" + single_colon + "]"
	  if ARGV[0][idx..-1].length > 1
	    setOption(compare, ARGV[0][(idx + 1)..-1])
	    opts[compare] = true
	    count += 1
	  elsif ARGV.length <= 1
	    return nil
	  else
	    setOption(compare, ARGV[1])
	    opts[compare] = true
	    ARGV.shift
	    count += 1
	  end
	  break
	end
      end
    else
      compare = ARGV[0]
      opts[compare] = true
      newargv << ARGV[0]
    end
    
    ARGV.shift
    if !opts.has_key?(compare)
      return nil
    end
  end
  setNewArgv(newargv)
  return count
end
