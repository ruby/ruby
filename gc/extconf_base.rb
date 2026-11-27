# frozen_string_literal: true

require "mkmf"

srcdir = File.join(__dir__, "..")
$INCFLAGS << " -I#{srcdir}"
$CPPFLAGS << " -DBUILDING_MODULAR_GC"

append_cflags("-fPIC")

DTRACE_RULES = <<~MAKE

  probes.stamp: $(GC_DTRACE_OBJS)
  	$(Q) if test -f $@ -o -f $(GC_DTRACE_OBJ); then \
  	  $(RM) $(GC_DTRACE_OBJS) $@; \
  	  $(ECHO) rebuilding objects which were modified by "dtrace -G"; \
  	  $(MAKE) $(GC_DTRACE_OBJS); \
  	fi
  	$(Q) touch $@

  $(GC_DTRACE_OBJ): $(top_srcdir)/probes.d $(GC_DTRACE_REBUILD:yes=probes.stamp)
  	$(ECHO) processing GC probes in object files
  	$(Q) CC="$(CC)" CFLAGS="$(CFLAGS) $(INCFLAGS) $(CPPFLAGS)" $(GC_DTRACE) -G -C $(INCFLAGS) -s $(top_srcdir)/probes.d -o $@ $(GC_DTRACE_OBJS)
MAKE

def create_gc_makefile(name, &block)
  dtrace_obj = ENV.fetch("DTRACE_OBJ", "")
  dtrace_enabled = (name == "default" && !dtrace_obj.empty?)

  if name == "default"
    $INCFLAGS << " -I$(topdir)"
    $headers << "$(topdir)/probes.h"
    $cleanfiles << "probes.stamp"
  end

  create_makefile("librubygc.#{name}") do |conf|
    conf = block.call(conf) if block
    next conf unless dtrace_enabled

    gc_objs = $objs.join(" ")
    conf = Array(conf).join.sub(/^OBJS = .*$/, "OBJS = #{gc_objs} #{dtrace_obj}")
    conf + <<~MAKE

    \tGC_DTRACE = #{ENV.fetch("DTRACE")}
    \tGC_DTRACE_OBJ = #{dtrace_obj}
    \tGC_DTRACE_OBJS = #{gc_objs}
    \tGC_DTRACE_REBUILD = #{ENV.fetch("DTRACE_REBUILD", "")}
    MAKE
  end

  File.write("Makefile", DTRACE_RULES, mode: "ab") if dtrace_enabled
end
