#! ./miniruby

# Used when making Ruby to generate node_name.inc.
# See common.mk for details.

while gets
  if ~/enum node_type \{/..~/^\};/
    ~/(NODE_.+),/ and puts("      case #{$1}:\n\treturn \"#{$1}\";")
  end
end
