# $Id$

def main
  if ARGV.first == '-a'
    with_arity = true
    ARGV.delete_at 0
  else
    with_arity = false
  end
  extract_ids(ARGF).sort.each do |id|
    if with_arity
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
