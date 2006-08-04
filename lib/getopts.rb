#
#               getopts.rb - 
#                       $Release Version: $
#                       $Revision$
#                       $Date$
#                       by Yasuo OHBA(SHL Japan Inc. Technology Dept.)
#
# --
# this is obsolete; use getoptlong
#
# 2000-03-21
# modified by Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
# 2002-03-05
# rewritten by Akinori MUSHA <knu@ruby-lang.org>
#

warn "Warning:#{caller[0].sub(/:in `.*'\z/, '')}: getopts is deprecated after Ruby 1.8.1; use optparse instead" if caller[0] and $VERBOSE

$RCS_ID=%q$Header$

# getopts is obsolete. Use GetoptLong.

def getopts(single_options, *options)
  boolopts = {}
  valopts = {}

  #
  # set defaults
  #
  single_options.scan(/.:?/) do |opt|
    if opt.size == 1
      boolopts[opt] = false
    else
      valopts[opt[0, 1]] = nil
    end
  end if single_options

  options.each do |arg|
    opt, val = arg.split(':', 2)

    if val
      valopts[opt] = val.empty? ? nil : val
    else
      boolopts[opt] = false
    end
  end

  #
  # scan
  #
  c = 0
  argv = ARGV

  while arg = argv.shift
    case arg
    when /\A--(.*)/
      if $1.empty?			# xinit -- -bpp 24
	break
      end

      opt, val = $1.split('=', 2)

      if opt.size == 1
	argv.unshift arg
	return nil
      elsif valopts.key? opt		# imclean --src +trash
	valopts[opt] = val || argv.shift or return nil
      elsif boolopts.key? opt		# ruby --verbose
	boolopts[opt] = true
      else
	argv.unshift arg
	return nil
      end

      c += 1
    when /\A-(.+)/
      opts = $1

      until opts.empty?
	opt = opts.slice!(0, 1)

	if valopts.key? opt
	  val = opts

	  if val.empty?			# ruby -e 'p $:'
	    valopts[opt] = argv.shift or return nil
	  else				# cc -ohello ...
	    valopts[opt] = val
	  end

	  c += 1
	  break
	elsif boolopts.key? opt
	  boolopts[opt] = true		# ruby -h
	  c += 1
	else
	  argv.unshift arg
	  return nil
	end
      end
    else
      argv.unshift arg
      break
    end
  end

  #
  # set
  #
  $OPT = {}

  boolopts.each do |opt, val|
    $OPT[opt] = val

    sopt = opt.gsub(/[^A-Za-z0-9_]/, '_')
    eval "$OPT_#{sopt} = val"
  end
  valopts.each do |opt, val|
    $OPT[opt] = val

    sopt = opt.gsub(/[^A-Za-z0-9_]/, '_')
    eval "$OPT_#{sopt} = val"
  end

  c
end
