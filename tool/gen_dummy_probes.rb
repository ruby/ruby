#!/usr/bin/ruby
# -*- coding: us-ascii -*-

# Used to create dummy probes (as for systemtap and DTrace) by Makefiles.
# See common.mk.

text = ARGF.read

# remove comments
text.gsub!(%r'(?:^ *)?/\*.*?\*/\n?'m, '')

# remove the pragma declarations and ifdefs
text.gsub!(/^#(?:pragma|include|if|endif).*\n/, '')

# replace the provider section with the start of the header file
text.gsub!(/provider ruby \{/, "#ifndef\t_PROBES_H\n#define\t_PROBES_H\n#define DTRACE_PROBES_DISABLED 1\n")

# finish up the #ifndef sandwich
text.gsub!(/\};/, "\n#endif\t/* _PROBES_H */")

# expand probes to DTRACE macros
text.gsub!(/^ *probe ([^\(]*)\(([^\)]*)\);/) {
  name, args = $1, $2
  name.upcase!
  name.gsub!(/__/, '_')
  args.gsub!(/(\A|, *)[^,]*\b(?=\w+(?=,|\z))/, '\1')
  "#define RUBY_DTRACE_#{name}_ENABLED() 0\n" \
  "#define RUBY_DTRACE_#{name}(#{args}) do {} while (0)"
}

puts "/* -*- c -*- */"
print text
