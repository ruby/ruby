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

$RCS_ID=%q$Header$


def getopts( single_opts, *options )
  single_opts_exp = (single_opts && !single_opts.empty?) ?
                        /[#{single_opts}]/ : nil
  single_colon_exp = nil
  single_colon = nil
  opt = arg = val = nil
  boolopts = {}
  valopts = {}
  argv = ARGV
  newargv = []

  #
  # set default
  #
  if single_opts then
    single_opts.each_byte do |byte|
      boolopts[ byte.chr ] = false
  end
end
  unless options.empty? then
    single_colon = ''

    options.each do |opt|
      m = /\A([^:]+):(.*)\z/.match( opt )
      if m then
        valopts[ m[1] ] = m[2].empty? ? 0 : m[2]
      else
        boolopts[ opt ] = false
end
  end
    valopts.each do |opt, dflt|
      if opt.size == 1 then
        single_colon << opt
end
  end

    if single_colon.empty? then
      single_colon = single_colon_exp = nil
      else
      single_colon_exp = /[#{single_colon}]/
    end
  end
  
  #
  # scan
  #
  c = 0
  arg = argv.shift
  while arg do
    case arg
    when /\A--?\z/                      # xinit -- -bpp 24
      newargv.concat argv
      break

    when /\A--(.*)/
      opt = $1
      if valopts.key? opt  then         # imclean --src +trash
        return nil if argv.empty?
        valopts[ opt ] = argv.shift
      elsif boolopts.key? opt then      # ruby --verbose
        boolopts[ opt ] = true
      else
              return nil
            end
      c += 1

    when /\A-(.+)/
      arg = $1
      0.upto( arg.size - 1 ) do |idx|
        opt = arg[idx, 1]
        if single_opts and single_opts_exp === opt then
          boolopts[ opt ] = true        # ruby -h
          c += 1

        elsif single_colon and single_colon_exp === opt then
          val = arg[ (idx+1)..-1 ]
          if val.empty? then            # ruby -e 'p $:'
            return nil if argv.empty?
            valopts[ opt ] = argv.shift
          else                          # cc -ohello ...
            valopts[ opt ] = val
      end
          c += 1

          break
          else
          return nil
          end
        end

    else                                # ruby test.rb
      newargv.push arg
      end

    arg = argv.shift
    end
    
  #
  # set
  #
  boolopts.each do |opt, val|
    eval "$OPT_#{opt} = val"
    end
  valopts.each do |opt, val|
    eval "$OPT_#{opt} = #{val == 0 ? 'nil' : 'val'}"
  end
  argv.replace newargv

  c
end
