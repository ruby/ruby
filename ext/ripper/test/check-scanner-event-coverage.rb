def main
  not_tested = eventids() - tested_ids()
  unless not_tested.empty?
    puts not_tested
    exit 1
  end
  exit 0
end

def eventids
  File.read('eventids2.c').scan(/on__(\w+)/).flatten.uniq
end

def tested_ids
  File.read('test/test_scanner_events.rb').scan(/def test_(\S+)/).flatten.uniq
end

main
