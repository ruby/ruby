case
when have_func("rb_w32_system_tmpdir")
  ok = true # win32
else
end
create_makefile("tmpdir") if ok
