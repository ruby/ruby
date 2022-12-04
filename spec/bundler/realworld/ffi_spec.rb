# frozen_string_literal: true

RSpec.describe "loading dinamically linked library on a bundle exec context", :realworld => true do
  it "passes ENV right after argv in memory" do
    create_file "foo.rb", <<~RUBY
      require 'ffi'

      module FOO
        extend FFI::Library
        ffi_lib './libfoo.so'

        attach_function :Hello, [], :void
      end

      FOO.Hello()
    RUBY

    create_file "libfoo.c", <<~'C'
      #include <stdio.h>

      static int foo_init(int argc, char** argv, char** envp) {
        if (argv[argc+1] == NULL) {
          printf("FAIL\n");
        } else {
          printf("OK\n");
        }

        return 0;
      }

      #if defined(__APPLE__) && defined(__MACH__)
      __attribute__((section("__DATA,__mod_init_func"), used, aligned(sizeof(void*))))
      #else
      __attribute__((section(".init_array")))
      #endif
      static void *ctr = &foo_init;

      extern char** environ;

      void Hello() {
        return;
      }
    C

    sys_exec "gcc -g -o libfoo.so -shared -fpic libfoo.c"

    install_gemfile <<-G
      source "https://rubygems.org"

      gem 'ffi'
    G

    bundle "exec ruby foo.rb"

    expect(out).to eq("OK")
  end
end
