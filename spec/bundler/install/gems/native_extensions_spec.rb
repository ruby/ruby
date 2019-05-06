# frozen_string_literal: true

RSpec.describe "installing a gem with native extensions", :ruby_repo do
  it "installs" do
    build_repo2 do
      build_gem "c_extension" do |s|
        s.extensions = ["ext/extconf.rb"]
        s.write "ext/extconf.rb", <<-E
          require "mkmf"
          name = "c_extension_bundle"
          dir_config(name)
          raise "OMG" unless with_config("c_extension") == "hello"
          create_makefile(name)
        E

        s.write "ext/c_extension.c", <<-C
          #include "ruby.h"

          VALUE c_extension_true(VALUE self) {
            return Qtrue;
          }

          void Init_c_extension_bundle() {
            VALUE c_Extension = rb_define_class("CExtension", rb_cObject);
            rb_define_method(c_Extension, "its_true", c_extension_true, 0);
          }
        C

        s.write "lib/c_extension.rb", <<-C
          require "c_extension_bundle"
        C
      end
    end

    gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
      gem "c_extension"
    G

    bundle "config set build.c_extension --with-c_extension=hello"
    bundle "install"

    expect(out).not_to include("extconf.rb failed")
    expect(out).to include("Installing c_extension 1.0 with native extensions")

    run "Bundler.require; puts CExtension.new.its_true"
    expect(out).to eq("true")
  end

  it "installs from git" do
    build_git "c_extension" do |s|
      s.extensions = ["ext/extconf.rb"]
      s.write "ext/extconf.rb", <<-E
        require "mkmf"
        name = "c_extension_bundle"
        dir_config(name)
        raise "OMG" unless with_config("c_extension") == "hello"
        create_makefile(name)
      E

      s.write "ext/c_extension.c", <<-C
        #include "ruby.h"

        VALUE c_extension_true(VALUE self) {
          return Qtrue;
        }

        void Init_c_extension_bundle() {
          VALUE c_Extension = rb_define_class("CExtension", rb_cObject);
          rb_define_method(c_Extension, "its_true", c_extension_true, 0);
        }
      C

      s.write "lib/c_extension.rb", <<-C
        require "c_extension_bundle"
      C
    end

    bundle! "config set build.c_extension --with-c_extension=hello"

    install_gemfile! <<-G
      gem "c_extension", :git => #{lib_path("c_extension-1.0").to_s.dump}
    G

    expect(out).not_to include("extconf.rb failed")

    run! "Bundler.require; puts CExtension.new.its_true"
    expect(out).to eq("true")
  end

  it "install with multiple build flags" do
    build_git "c_extension" do |s|
      s.extensions = ["ext/extconf.rb"]
      s.write "ext/extconf.rb", <<-E
        require "mkmf"
        name = "c_extension_bundle"
        dir_config(name)
        raise "OMG" unless with_config("c_extension") == "hello" && with_config("c_extension_bundle-dir") == "hola"
        create_makefile(name)
      E

      s.write "ext/c_extension.c", <<-C
        #include "ruby.h"

        VALUE c_extension_true(VALUE self) {
          return Qtrue;
        }

        void Init_c_extension_bundle() {
          VALUE c_Extension = rb_define_class("CExtension", rb_cObject);
          rb_define_method(c_Extension, "its_true", c_extension_true, 0);
        }
      C

      s.write "lib/c_extension.rb", <<-C
        require "c_extension_bundle"
      C
    end

    bundle! "config set build.c_extension --with-c_extension=hello --with-c_extension_bundle-dir=hola"

    install_gemfile! <<-G
      gem "c_extension", :git => #{lib_path("c_extension-1.0").to_s.dump}
    G

    expect(out).not_to include("extconf.rb failed")

    run! "Bundler.require; puts CExtension.new.its_true"
    expect(out).to eq("true")
  end
end
