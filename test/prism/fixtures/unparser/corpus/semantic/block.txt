foo do
end

foo do
rescue
end

foo do
  nil rescue nil
  nil
end

foo do |a|
end

foo(<<-DOC) do |a|
  b
DOC
  a
end

foo(<<-DOC) do
  b
DOC
  a
end
