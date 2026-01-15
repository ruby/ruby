begin
rescue
end

begin
ensure
end

begin
  a
end

begin
  a
rescue
  b
end

begin
  a
  b
rescue
  b
end

begin
rescue A
end

begin
rescue A => foo
end

begin
  a
rescue A
  b
rescue B
  c
ensure
  d
end

begin
  begin
    foo
    bar
  rescue
  end
rescue
  baz
  bar
end

begin
  raise(Exception) rescue foo = bar
rescue Exception
end

begin
  foo
rescue => bar
  bar
end

begin
  foo
rescue Exception, Other => bar
  bar
end

begin
  bar
rescue SomeError, *bar => exception
  baz
end

class << self
  undef :bar rescue nil
end
