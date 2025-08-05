require_relative 'templates/template'

puts %[
PRISM_TEMPLATES_DIR = $(PRISM_SRCDIR)/templates
PRISM_TEMPLATE = $(PRISM_TEMPLATES_DIR)/template.rb
PRISM_CONFIG = $(PRISM_SRCDIR)/config.yml
]

Prism::Template::TEMPLATES.map do |t|
  /\.(?:[ch]|rb)\z/ =~ t or next
  s = t.sub(%r[\A(?:(src)|ext|include)/]) {$1 && 'prism/'}
  puts %[
main srcs: $(srcdir)/#{s}
$(srcdir)/#{s}: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/#{t}.erb
\t$(Q) $(BASERUBY) $(PRISM_TEMPLATE) #{t} $@
]
end
