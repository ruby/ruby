<<-EOF
  a
EOF

<<-FIRST + <<-SECOND
  a
FIRST
  b
SECOND

<<-`EOF`
  a
#{b}
EOF

<<-EOF #comment
  a
EOF

<<-EOF
  a
  b
  EOF

<<-"EOF"
  a
#{b}
EOF

<<-EOF
  a
#{b}
EOF

%#abc#

<<-EOF
  a
  b
EOF

<<-'EOF'
  a #{1}
EOF
