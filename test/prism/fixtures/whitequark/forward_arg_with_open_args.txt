(def foo ...
  bar(...)
end)

(def foo ...; bar(...); end)

def foo ...
end

def foo ...; bar(...); end

def foo a, ...
  bar(...)
end

def foo a, ...; bar(...); end

def foo a, b = 1, ...
end

def foo b = 1, ...
  bar(...)
end

def foo b = 1, ...; bar(...); end

def foo(a, ...) bar(...) end
