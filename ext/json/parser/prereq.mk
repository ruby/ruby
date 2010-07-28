RAGEL = ragel

.SUFFIXES: .rl

.rl.c:
	$(RAGEL) -G2 $<

parser.c:
