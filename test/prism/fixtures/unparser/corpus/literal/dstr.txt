if true
  "#{}a"
end
if true
  <<-HEREDOC
a
#{}a
b
  HEREDOC
  x
end
<<-HEREDOC
\#{}\#{}
#{}
#{}
#{}
HEREDOC
<<-HEREDOC rescue nil
#{}
a
HEREDOC
"a#$1"
"a#$a"
"a#@a"
"a#@@a"
if true
  return <<-HEREDOC
    #{42}
  HEREDOC
end
foo(<<-HEREDOC)
  #{bar}
HEREDOC
foo(<<-HEREDOC) { |x|
  #{bar}
HEREDOC
}
