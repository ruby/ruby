#!/usr/bin/ruby
# -*- coding: us-ascii -*-

text = ARGF.read
text.gsub!(/^(?!#)(.*)/){$1.upcase}

# remove comments
text.gsub!(%r'(?:^ *)?/\*.*?\*/\n?'m, '')

# remove the pragma declarations
text.gsub!(/^#pragma.*\n/, '')

# replace the provider section with the start of the header file
text.gsub!(/PROVIDER RUBY \{/, "#ifndef\t_PROBES_H\n#define\t_PROBES_H\n#define DTRACE_PROBES_DISABLED 1\n")

# finish up the #ifndef sandwich
text.gsub!(/\};/, "\n#endif\t/* _PROBES_H */")

text.gsub!(/__/, '_')

text.gsub!(/\((.+?)(?=\);)/) {
  "(arg" << (0..$1.count(',')).to_a.join(", arg")
}

text.gsub!(/ *PROBE ([^\(]*)(\([^\)]*\));/, "#define RUBY_DTRACE_\\1_ENABLED() 0\n#define RUBY_DTRACE_\\1\\2\ do \{ \} while\(0\)")
puts "/* -*- c -*- */"
print text

