#
# list-parse-event-ids.rb
#

require 'getopts'

def usage( status )
  (status == 0 ? $stdout : $stderr).print(<<EOS)
Usage: #{File.basename($0)} [-a] filename
EOS
  exit status
end

def main
  getopts('a') or usage(1)
  extract_ids(ARGF).each do |id, arity|
    if $OPT_a
    then puts "#{id} #{arity}"
    else puts id
    end
  end
end

def extract_ids( f )
  results = []
  f.each do |line|
    next if /\A\#\s*define\s+s?dispatch/ === line
    next if /ripper_dispatch/ === line
    if a = line.scan(/dispatch(\d)\((\w+)/)
      a.each do |arity, event|
        results.push [event, arity.to_i]
      end
    end
  end
  results.uniq.sort
end

main
