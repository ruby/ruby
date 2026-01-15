exclude(:test_daemon_no_threads, "MMTk spawns worker threads after fork")
exclude(:test_warmup_frees_pages, "testing behaviour specific to default GC")
exclude(:test_warmup_promote_all_objects_to_oldgen, "testing behaviour specific to default GC")
exclude(:test_warmup_run_major_gc_and_compact, "testing behaviour specific to default GC")
