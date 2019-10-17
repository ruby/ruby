#! ./miniruby -n

# Used when making Ruby to generate node_name.inc.
# See common.mk for details.

if (t ||= /^enum node_type \{/ =~ $_) and (t = /^\};/ !~ $_)
  /(NODE_.+),/ =~ $_ and puts("      case #{$1}:\n\treturn \"#{$1}\";")
end
