.SUFFIXES: .list

.list.h:
	gperf -E -C -c -P -p -j1 -i 1 -g -o -t -N $(*F) $< \
	| sed 's/(int)(long)&((\(struct stringpool_t\) *\*)0)->\(stringpool_[a-z0-9]*\)/offsetof(\1, \2)/g' \
	> $(@F)

zonetab.h: zonetab.list
