.SUFFIXES: .list

.list.h:
	gperf -E -C -c -P -p -j1 -i 1 -g -o -t -N $(*F) $< \
	| sed -f $(top_srcdir)/tool/gperf.sed \
	> $(@F)

zonetab.h: zonetab.list
