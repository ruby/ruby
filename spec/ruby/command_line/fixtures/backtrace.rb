def a
  raise 'oops'
end

def b
  a
end

def c
  b
end

def d
  c
end

arg = ARGV.first
$stderr.puts arg

case arg
when 'full_message'
  begin
    d
  rescue => exc
    puts exc.full_message
  end
when 'backtrace'
  begin
    d
  rescue => exc
    puts exc.backtrace
  end
else
  d
end
