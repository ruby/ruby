def foo(argument, **)
  bar(argument, **)
end

def foo(argument, *)
  bar(argument, *)
end

def foo(**)
  { default: 1, ** }
end
