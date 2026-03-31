set height 0
set width 0
set confirm off

echo \n>>> Threads\n\n
info threads

echo \n>>> Machine level backtrace\n\n
thread apply all info stack full

echo \n>>> Dump Ruby level backtrace (if possible)\n\n
call rb_vmdebug_stack_dump_all_threads()
call fflush(stderr)

echo ">>> Finish\n"
detach
quit
