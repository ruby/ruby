# frozen_string_literal: true

RSpec.describe "installing a gem with native extensions" do
  it "installs" do
    build_repo2 do
      build_gem "c_extension" do |s|
        s.extensions = ["ext/extconf.rb"]
        s.write "ext/extconf.rb", <<-E
          require "mkmf"
          $extout = "$(topdir)/" + RbConfig::CONFIG["EXTOUT"] unless RUBY_VERSION < "2.4"
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

    expect(out).to include("Installing c_extension 1.0 with native extensions")

    run "Bundler.require; puts CExtension.new.its_true"
    expect(out).to eq("true")
  end

  it "installs from git" do
    build_git "c_extension" do |s|
      s.extensions = ["ext/extconf.rb"]
      s.write "ext/extconf.rb", <<-E
        require "mkmf"
        $extout = "$(topdir)/" + RbConfig::CONFIG["EXTOUT"] unless RUBY_VERSION < "2.4"
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

    bundle "config set build.c_extension --with-c_extension=hello"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "c_extension", :git => #{lib_path("c_extension-1.0").to_s.dump}
    G

    expect(err).to_not include("warning: conflicting chdir during another chdir block")

    run "Bundler.require; puts CExtension.new.its_true"
    expect(out).to eq("true")
  end

  it "installs correctly from git when multiple gems with extensions share one repository" do
    build_repo2 do
      ["one", "two"].each do |n|
        build_lib "c_extension_#{n}", "1.0", :path => lib_path("gems/c_extension_#{n}") do |s|
          s.extensions = ["ext/extconf.rb"]
          s.write "ext/extconf.rb", <<-E
            require "mkmf"
            $extout = "$(topdir)/" + RbConfig::CONFIG["EXTOUT"] unless RUBY_VERSION < "2.4"
            name = "c_extension_bundle_#{n}"
            dir_config(name)
            raise "OMG" unless with_config("c_extension_#{n}") == "#{n}"
            create_makefile(name)
          E

          s.write "ext/c_extension_#{n}.c", <<-C
            #include "ruby.h"

            VALUE c_extension_#{n}_value(VALUE self) {
              return rb_str_new_cstr("#{n}");
            }

            void Init_c_extension_bundle_#{n}() {
              VALUE c_Extension = rb_define_class("CExtension_#{n}", rb_cObject);
              rb_define_method(c_Extension, "value", c_extension_#{n}_value, 0);
            }
          C

          s.write "lib/c_extension_#{n}.rb", <<-C
            require "c_extension_bundle_#{n}"
          C
        end
      end
      build_git "gems", :path => lib_path("gems"), :gemspec => false
    end

    bundle "config set build.c_extension_one --with-c_extension_one=one"
    bundle "config set build.c_extension_two --with-c_extension_two=two"

    # 1st time, require only one gem -- only one of the extensions gets built.
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "c_extension_one", :git => #{lib_path("gems").to_s.dump}
    G

    # 2nd time, require both gems -- we need both extensions to be built now.
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "c_extension_one", :git => #{lib_path("gems").to_s.dump}
      gem "c_extension_two", :git => #{lib_path("gems").to_s.dump}
    G

    run "Bundler.require; puts CExtension_one.new.value; puts CExtension_two.new.value"
    expect(out).to eq("one\ntwo")
  end

  it "install with multiple build flags" do
    build_git "c_extension" do |s|
      s.extensions = ["ext/extconf.rb"]
      s.write "ext/extconf.rb", <<-E
        require "mkmf"
        $extout = "$(topdir)/" + RbConfig::CONFIG["EXTOUT"] unless RUBY_VERSION < "2.4"
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

    bundle "config set build.c_extension --with-c_extension=hello --with-c_extension_bundle-dir=hola"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "c_extension", :git => #{lib_path("c_extension-1.0").to_s.dump}
    G

    run "Bundler.require; puts CExtension.new.its_true"
    expect(out).to eq("true")
  end
end
