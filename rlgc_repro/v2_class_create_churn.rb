# RLGCv2 regression: concurrent Class.new across Ractors updates the VM-shared
# subclass list (class_switch_superclass -> push_subclass_entry_to_list) whose
# write barrier, under RGENGC_CHECK_MODE, ran check_rvalue_consistency_force ->
# verify_pointer_in_any_heap_p. That bsearches every objspace's heap_pages.sorted
# while holding only the no-barrier VM lock, racing other Ractors' confined
# allocation reallocating those arrays -> SEGV in bsearch. (bootstraptest
# test_ractor.rb #144 "Creating classes inside of Ractors", [Bug #18119].)
# Crashed ~2/200 under v2-debug before; must be 0 after.
port = Ractor::Port.new
workers = (0...8).map do
  Ractor.new port do |port|
    loop do
      100.times.map { Class.new }
      port << nil
    end
  end
end
100.times { port.receive }
puts 'OK v2_class_create_churn'
