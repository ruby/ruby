# FIXME: when ractor-local GC (rlgc) lands, see if it's fixed.
exclude(:test_compaction, "GC.compact crashes")
