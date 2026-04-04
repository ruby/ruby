PRISM_TEMPLATES_DIR = $(PRISM_SRCDIR)/templates
PRISM_TEMPLATE = $(PRISM_TEMPLATES_DIR)/template.rb
PRISM_CONFIG = $(PRISM_SRCDIR)/config.yml

srcs uncommon.mk: prism/.srcs.mk.time

prism/.srcs.mk.time: $(order_only) $(PRISM_BUILD_DIR)/.time
prism/$(HAVE_BASERUBY:no=.srcs.mk.time):
	touch $@
prism/$(HAVE_BASERUBY:yes=.srcs.mk.time): \
		$(PRISM_SRCDIR)/templates/template.rb \
		$(PRISM_SRCDIR)/srcs.mk.in
	$(BASERUBY) $(tooldir)/generic_erb.rb -c -t$@ -o $(PRISM_SRCDIR)/srcs.mk $(PRISM_SRCDIR)/srcs.mk.in

distclean-prism-srcs::
	$(RM) prism/.srcs.mk.time
	$(RMDIRS) prism || $(NULLCMD)

distclean-srcs-local:: distclean-prism-srcs

realclean-prism-srcs:: distclean-prism-srcs
	$(RM) $(PRISM_SRCDIR)/srcs.mk

realclean-srcs-local:: realclean-prism-srcs

main srcs: prism-srcs
main incs: prism-incs

prism-srcs: $(srcdir)/prism/api_node.c
$(srcdir)/prism/api_node.c: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/ext/prism/api_node.c.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) ext/prism/api_node.c $@

realclean-prism-srcs::
	$(RM) $(srcdir)/prism/api_node.c

prism-incs: $(srcdir)/prism/ast.h
$(srcdir)/prism/ast.h: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/include/prism/ast.h.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) include/prism/ast.h $@

realclean-prism-srcs::
	$(RM) $(srcdir)/prism/ast.h

prism-incs: $(srcdir)/prism/internal/diagnostic.h
$(srcdir)/prism/internal/diagnostic.h: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/include/prism/internal/diagnostic.h.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) include/prism/internal/diagnostic.h $@

realclean-prism-srcs::
	$(RM) $(srcdir)/prism/internal/diagnostic.h

prism-srcs: $(srcdir)/lib/prism/compiler.rb
$(srcdir)/lib/prism/compiler.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/compiler.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/compiler.rb $@

realclean-prism-srcs::
	$(RM) $(srcdir)/lib/prism/compiler.rb

prism-srcs: $(srcdir)/lib/prism/dispatcher.rb
$(srcdir)/lib/prism/dispatcher.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/dispatcher.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/dispatcher.rb $@

realclean-prism-srcs::
	$(RM) $(srcdir)/lib/prism/dispatcher.rb

prism-srcs: $(srcdir)/lib/prism/dot_visitor.rb
$(srcdir)/lib/prism/dot_visitor.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/dot_visitor.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/dot_visitor.rb $@

realclean-prism-srcs::
	$(RM) $(srcdir)/lib/prism/dot_visitor.rb

prism-srcs: $(srcdir)/lib/prism/dsl.rb
$(srcdir)/lib/prism/dsl.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/dsl.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/dsl.rb $@

realclean-prism-srcs::
	$(RM) $(srcdir)/lib/prism/dsl.rb

prism-srcs: $(srcdir)/lib/prism/inspect_visitor.rb
$(srcdir)/lib/prism/inspect_visitor.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/inspect_visitor.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/inspect_visitor.rb $@

realclean-prism-srcs::
	$(RM) $(srcdir)/lib/prism/inspect_visitor.rb

prism-srcs: $(srcdir)/lib/prism/mutation_compiler.rb
$(srcdir)/lib/prism/mutation_compiler.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/mutation_compiler.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/mutation_compiler.rb $@

realclean-prism-srcs::
	$(RM) $(srcdir)/lib/prism/mutation_compiler.rb

prism-srcs: $(srcdir)/lib/prism/node.rb
$(srcdir)/lib/prism/node.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/node.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/node.rb $@

realclean-prism-srcs::
	$(RM) $(srcdir)/lib/prism/node.rb

prism-srcs: $(srcdir)/lib/prism/reflection.rb
$(srcdir)/lib/prism/reflection.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/reflection.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/reflection.rb $@

realclean-prism-srcs::
	$(RM) $(srcdir)/lib/prism/reflection.rb

prism-srcs: $(srcdir)/lib/prism/serialize.rb
$(srcdir)/lib/prism/serialize.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/serialize.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/serialize.rb $@

realclean-prism-srcs::
	$(RM) $(srcdir)/lib/prism/serialize.rb

prism-srcs: $(srcdir)/lib/prism/visitor.rb
$(srcdir)/lib/prism/visitor.rb: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/lib/prism/visitor.rb.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) lib/prism/visitor.rb $@

realclean-prism-srcs::
	$(RM) $(srcdir)/lib/prism/visitor.rb

prism-srcs: $(srcdir)/prism/diagnostic.c
$(srcdir)/prism/diagnostic.c: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/src/diagnostic.c.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) src/diagnostic.c $@

realclean-prism-srcs::
	$(RM) $(srcdir)/prism/diagnostic.c

prism-srcs: $(srcdir)/prism/json.c
$(srcdir)/prism/json.c: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/src/json.c.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) src/json.c $@

realclean-prism-srcs::
	$(RM) $(srcdir)/prism/json.c

prism-srcs: $(srcdir)/prism/node.c
$(srcdir)/prism/node.c: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/src/node.c.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) src/node.c $@

realclean-prism-srcs::
	$(RM) $(srcdir)/prism/node.c

prism-srcs: $(srcdir)/prism/prettyprint.c
$(srcdir)/prism/prettyprint.c: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/src/prettyprint.c.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) src/prettyprint.c $@

realclean-prism-srcs::
	$(RM) $(srcdir)/prism/prettyprint.c

prism-srcs: $(srcdir)/prism/serialize.c
$(srcdir)/prism/serialize.c: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/src/serialize.c.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) src/serialize.c $@

realclean-prism-srcs::
	$(RM) $(srcdir)/prism/serialize.c

prism-srcs: $(srcdir)/prism/tokens.c
$(srcdir)/prism/tokens.c: $(PRISM_CONFIG) $(PRISM_TEMPLATE) $(PRISM_TEMPLATES_DIR)/src/tokens.c.erb
	$(Q) $(BASERUBY) $(PRISM_TEMPLATE) src/tokens.c $@

realclean-prism-srcs::
	$(RM) $(srcdir)/prism/tokens.c
