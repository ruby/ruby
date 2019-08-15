# This script was needed only once when I converted the old insns.def.
# Consider historical.
#
# ruby converter.rb insns.def | sponge insns.def

BEGIN { $str = ARGF.read }
END   { puts $str }

# deal with spaces
$str.gsub! %r/\r\n|\r|\n|\z/, "\n"
$str.gsub! %r/([^\t\n]*)\t/ do
  x = $1
  y = 8 - x.length % 8
  next x + ' ' * y
end
$str.gsub! %r/\s+$/, "\n"

# deal with comments
$str.gsub! %r/@c.*?@e/m, ''
$str.gsub! %r/@j.*?\*\//m, '*/'
$str.gsub! %r/\n(\s*\n)+/, "\n\n"
$str.gsub! %r/\/\*\*?\s*\n\s*/, "/* "
$str.gsub! %r/\n\s+\*\//, " */"
$str.gsub! %r/^(?!.*\/\*.+\*\/$)(.+?)\s*\*\//, "\\1\n */"

# deal with sp_inc
$str.gsub! %r/ \/\/ inc -= (.*)/, ' // inc += -\\1'
$str.gsub! %r/\s+\/\/ inc \+= (.*)/, "\n// attr rb_snum_t sp_inc = \\1;"
$str.gsub! %r/;;$/, ";"
