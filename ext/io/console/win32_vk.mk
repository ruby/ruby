win32_vk.inc: win32_vk.list $(srcdir)/extract-vk.rb

.list.inc:
	$(Q)$(RUBY) $(srcdir)/extract-vk.rb $< \
	    --ignore-case -L ANSI-C -E -C -P -p -j1 -i 1 -g -o -t -K ofs -N console_win32_vk -k* \
	    > $(@F)

.SUFFIXES: .chksum .list .inc

.list.chksum:
	@$(RUBY) -I$(top_srcdir)/tool -rchecksum \
	    -e "Checksum.update(ARGV) {|k|k.copy(k.target) rescue k.make(k.target)}" \
	    -- --make=$(MAKE) -I$(srcdir) $(<F) $(@F:.chksum=.inc)
