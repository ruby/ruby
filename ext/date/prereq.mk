.SUFFIXES: .list

.list.h:
	gperf --ignore-case -C -c -P -p -j1 -i 1 -g -o -t -N $(*F) $< \
	| sed -f $(top_srcdir)/tool/gperf.sed \
	> $(@F)

zonetab.h: zonetab.list

.PHONY: update-zonetab
update-zonetab:
	$(RUBY) -C $(srcdir) update-abbr.rb
