PRISM_TEMPLATES_DIR = $(PRISM_SRCDIR)/templates
PRISM_TEMPLATE = $(PRISM_TEMPLATES_DIR)/template.rb
PRISM_CONFIG = $(PRISM_SRCDIR)/config.yml

srcs uncommon.mk: prism/.srcs.mk.time

prism/.srcs.mk.time:
prism/$(HAVE_BASERUBY:yes=.srcs.mk.time): \
		$(PRISM_SRCDIR)/templates/template.rb \
		$(PRISM_SRCDIR)/srcs.mk.in
	$(BASERUBY) $(tooldir)/generic_erb.rb -c -t$@ -o $(PRISM_SRCDIR)/srcs.mk $(PRISM_SRCDIR)/srcs.mk.in

realclean-prism-srcs::
	$(RM) $(PRISM_SRCDIR)/srcs.mk

realclean-srcs-local:: realclean-prism-srcs

main srcs: $(PRISM_SRCDIR)/api_node.c
$(PRISM_SRCDIR)/api_node.c: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/ext/prism/api_node.c.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) ext/prism/api_node.c $@

realclean-prism-srcs::
	$(RM) $(PRISM_SRCDIR)/api_node.c

main incs: $(PRISM_SRCDIR)/ast.h
$(PRISM_SRCDIR)/ast.h: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/include/prism/ast.h.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) include/prism/ast.h $@

realclean-prism-srcs::
	$(RM) $(PRISM_SRCDIR)/ast.h

main incs: $(PRISM_SRCDIR)/diagnostic.h
$(PRISM_SRCDIR)/diagnostic.h: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/include/prism/diagnostic.h.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) include/prism/diagnostic.h $@

realclean-prism-srcs::
	$(RM) $(PRISM_SRCDIR)/diagnostic.h

main srcs: lib/prism/compiler.rb
lib/prism/compiler.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/compiler.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/compiler.rb $@

realclean-prism-srcs::
	$(RM) lib/prism/compiler.rb

main srcs: lib/prism/dispatcher.rb
lib/prism/dispatcher.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/dispatcher.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/dispatcher.rb $@

realclean-prism-srcs::
	$(RM) lib/prism/dispatcher.rb

main srcs: lib/prism/dot_visitor.rb
lib/prism/dot_visitor.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/dot_visitor.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/dot_visitor.rb $@

realclean-prism-srcs::
	$(RM) lib/prism/dot_visitor.rb

main srcs: lib/prism/dsl.rb
lib/prism/dsl.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/dsl.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/dsl.rb $@

realclean-prism-srcs::
	$(RM) lib/prism/dsl.rb

main srcs: lib/prism/inspect_visitor.rb
lib/prism/inspect_visitor.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/inspect_visitor.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/inspect_visitor.rb $@

realclean-prism-srcs::
	$(RM) lib/prism/inspect_visitor.rb

main srcs: lib/prism/mutation_compiler.rb
lib/prism/mutation_compiler.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/mutation_compiler.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/mutation_compiler.rb $@

realclean-prism-srcs::
	$(RM) lib/prism/mutation_compiler.rb

main srcs: lib/prism/node.rb
lib/prism/node.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/node.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/node.rb $@

realclean-prism-srcs::
	$(RM) lib/prism/node.rb

main srcs: lib/prism/reflection.rb
lib/prism/reflection.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/reflection.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/reflection.rb $@

realclean-prism-srcs::
	$(RM) lib/prism/reflection.rb

main srcs: lib/prism/serialize.rb
lib/prism/serialize.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/serialize.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/serialize.rb $@

realclean-prism-srcs::
	$(RM) lib/prism/serialize.rb

main srcs: lib/prism/visitor.rb
lib/prism/visitor.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/visitor.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/visitor.rb $@

realclean-prism-srcs::
	$(RM) lib/prism/visitor.rb

main srcs: $(PRISM_SRCDIR)/diagnostic.c
$(PRISM_SRCDIR)/diagnostic.c: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/src/diagnostic.c.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) src/diagnostic.c $@

realclean-prism-srcs::
	$(RM) $(PRISM_SRCDIR)/diagnostic.c

main srcs: $(PRISM_SRCDIR)/node.c
$(PRISM_SRCDIR)/node.c: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/src/node.c.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) src/node.c $@

realclean-prism-srcs::
	$(RM) $(PRISM_SRCDIR)/node.c

main srcs: $(PRISM_SRCDIR)/prettyprint.c
$(PRISM_SRCDIR)/prettyprint.c: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/src/prettyprint.c.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) src/prettyprint.c $@

realclean-prism-srcs::
	$(RM) $(PRISM_SRCDIR)/prettyprint.c

main srcs: $(PRISM_SRCDIR)/serialize.c
$(PRISM_SRCDIR)/serialize.c: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/src/serialize.c.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) src/serialize.c $@

realclean-prism-srcs::
	$(RM) $(PRISM_SRCDIR)/serialize.c

main srcs: $(PRISM_SRCDIR)/token_type.c
$(PRISM_SRCDIR)/token_type.c: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/src/token_type.c.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) src/token_type.c $@

realclean-prism-srcs::
	$(RM) $(PRISM_SRCDIR)/token_type.c
