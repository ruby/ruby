trap('print("C-c handled\n")', 'INT', 'HUP')
print("---\n")
while gets(); print($_) end
