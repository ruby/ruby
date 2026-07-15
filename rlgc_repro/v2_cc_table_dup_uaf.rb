# RLGCv2 ASAN use-after-poison in the multi-Ractor cc-table copy-on-write dup.
#
# Captured by the confluence monitor on cf_move_compact_sender (move:+GC.compact);
# load-dependent (~1/many), so this is an amplifier, not a deterministic repro.
#
# Mechanism: on a method cache MISS for a SHARED class in multi-Ractor mode,
# cache_callable_method_entry (vm_method.c:1978, rb_multi_ractor_p branch) does a
# copy-on-write: rb_vm_cc_table_dup(old_cc_tbl) -> add entry -> RB_OBJ_ATOMIC_WRITE
# swaps the class's cc_tbl to the new table. The dup ITERATES the OLD table
# (rb_managed_id_table_foreach -> vm_cc_table_dup_i, vm_method.c:153 reads
# old_ccs->cme). Under RLGC, GC frees the OLD cc table's entries (ccs ruby_xfree'd
# via the managed-id-table dfree once the table is swapped away / collected) WHILE a
# concurrent Ractor is still iterating it -> read of a poisoned (asan_poison_object,
# shadow f7) slot. = shareable cc-table liveness gap: the old shared cc table held
# during a cross-Ractor dup is collected because that in-flight reference isn't
# keeping it alive (VM-global-table x per-Ractor-GC face).
#
# cc-table COW machinery is upstream (John Hawthorn d9c0d4c71c / Jean Boussier
# 547f111b5b, 0 RLGC markers); RLGC's per-Ractor GC frees the old table that the
# lock-free swap assumes stays alive for in-flight dups. Full stack:
# /tmp/claude/FINDING_cc_table_dup_uaf.md. Same family as the cc_refinement_set
# CHECK finding and the zombie-Ractor / fiber_free teardown UAFs.
#
# Run MANY concurrently under v2-asan to maximize load:
Warning[:experimental] = false
KS = Ractor.make_shareable((1..10).map { Class.new { (0..20).each { |m| define_method("m#{m}") { m } } } })
rs = (1..8).map do
  Ractor.new(KS) do |ks|
    250.times do |i|
      ks.each { |k| o = k.new; (0..20).each { |m| o.send("m#{m}") rescue nil } }
      GC.start if i % 8 == 0
    end
    :ok
  end
end
redef = Thread.new do
  120.times do |i|
    KS.each { |k| k.class_eval { define_method("m#{i % 21}") { i } } }
    GC.compact if i % 4 == 0
  end
end
rs.each(&:value); redef.join
