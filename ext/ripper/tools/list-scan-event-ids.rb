#
# list-scan-event-ids.rb
#

require 'getopts'

def usage(status)
  (status == 0 ? $stdout : $stderr).puts(<<EOS)
Usage: #{File.basename($0)} eventids2.c
    -a    print IDs with arity.
EOS
  exit status
end

def main
  ok = getopts('a', 'help')
  usage 0 if $OPT_help
  usage 1 unless ok
  extract_ids(ARGF).sort.each do |id|
    if $OPT_a
      puts "#{id} 1"
    else
      puts id
    end
  end
end

def extract_ids(f)
  (f.read.scan(/ripper_id_(\w+)/).flatten - ['scan']).uniq
end

main
