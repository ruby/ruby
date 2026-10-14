# frozen_string_literal: true

require_relative "../extconf_base"

module MMTkLTO
  module_function

  def detect
    return if ENV["MMTK_LTO"] == "0"

    rustc_info = `rustc --version --verbose 2>/dev/null`
    llvm = rustc_info[/^LLVM version: (\d+)/, 1] or return
    host = rustc_info[/^host: (\S+)/, 1] or return
    arch = host.start_with?("aarch64") ? "-mcpu=native" : "-march=native"

    candidates = if (cc = ENV["MMTK_LTO_CLANG"])
      [cc]
    else
      [CONFIG["CC"], "clang-#{llvm}", "clang",
       "/opt/homebrew/opt/llvm/bin/clang", "/usr/local/opt/llvm/bin/clang"]
    end

    candidates.compact.map { |cc| cc.split.first }.uniq.each do |cc|
      ver = `#{cc} --version 2>/dev/null`
      next if ver.include?("Apple") || ver[/clang version (\d+)/, 1] != llvm

      flag_sets = [[arch]]

      if host.include?("linux") && `#{cc} -dumpmachine 2>/dev/null`.strip != host
        flag_sets.unshift([arch, "-target", host])
      end

      if (flags = probe(cc, flag_sets))
        unless cc.include?("/")
          resolved = `command -v #{cc} 2>/dev/null`.strip
          cc = resolved unless resolved.empty?
        end

        return {cc: cc, cflags: flags[0], ldflags: flags[1], host: host}
      end
    end

    warn(<<~WARNING)
      WARNING: MMTk cross-language LTO disabled: no Clang matching rustc's LLVM #{llvm}.x found.
      The GC will still work, but calls across the C/Rust boundary will not be
      inlined. Set MMTK_LTO_CLANG to a matching Clang. Set MMTK_LTO=0 to
      silence this warning.
    WARNING
    nil
  end

  def probe(cc, flag_sets)
    require "tmpdir"
    Dir.mktmpdir("mmtk-lto-probe") do |dir|
      c = File.join(dir, "probe.c")
      rs = File.join(dir, "probe.rs")
      lib = File.join(dir, "libprobe.a")
      bin = File.join(dir, "probe")
      File.write(c, <<~C)
        #include <stdio.h>
        extern unsigned long rs_fn(unsigned long);
        int main(void) { printf("%lu", rs_fn(41)); return 0; }
      C
      File.write(rs, "#[no_mangle]\npub extern \"C\" fn rs_fn(x: usize) -> usize { x + 1 }\n")
      # -C lto mirrors [profile.release] lto in Cargo.toml; without it rustc
      # does not tag the bitcode for LTO and the linker never inlines it.
      system("rustc", "-O", "--crate-type", "staticlib", "-Clinker-plugin-lto",
             "-C", "lto", "-C", "target-cpu=native", rs, "-o", lib,
             out: File::NULL, err: File::NULL) or return
      # Also try lld: the default linker may lack the LLVM plugin for LTO.
      flag_sets.each do |cflags|
        [[], ["-fuse-ld=lld"]].each do |ldflags|
          if system(cc, "-O2", "-flto", *cflags, *ldflags, c, lib, "-o", bin,
                    out: File::NULL, err: File::NULL)
            return [cflags, ldflags]
          end
        end
      end
      nil
    end
  end

  def filter_warnflags(cc, flags)
    flags.split.select do |flag|
      system(cc, "-Werror=unknown-warning-option", flag, "-fsyntax-only",
             "-x", "c", File::NULL, out: File::NULL, err: File::NULL)
    end
  end
end

lto = MMTkLTO.detect
if lto
  puts("MMTk cross-language LTO enabled (cc: #{lto[:cc]})")
end

# Statically link `libmmtk_ruby.a`
$LIBS << " $(MMTK_BUILD)/$(LIBMMTK_RUBY)"

rustsrcs = Dir.glob("src/**/*.rs", base: __dir__).map {|s| "$(srcdir)/#{s}"}

create_gc_makefile("mmtk") do |makefile|
  conf = [
    *makefile,

    <<~MAKEFILE,
    MMTK_BUILD = debug
    LIBMMTK_RUBY = libmmtk_ruby.#$LIBEXT
    RUSTSRCS = #{rustsrcs.join(" \\\n\t   ")}

    ifeq ($(MMTK_BUILD), debug)
    CPPFLAGS += -DMMTK_DEBUG
    endif
    MAKEFILE
  ]

  if lto
    # Compile and link the C code with the Clang matching rustc's LLVM so
    # that the linker can inline across the C/Rust boundary. The Cargo flags
    # are scoped to the target triple (via --target) so that host-only crates
    # (build scripts and proc macros) are still linked by rustc as usual;
    # --target makes Cargo place the artifacts in <target triple>/release,
    # which MMTK_CARGO_FIXUP copies back to the expected location.
    cc = CONFIG["CC"].dup
    cc[/\A\s*\S+/] = lto[:cc]
    cflags = (["-flto"] + lto[:cflags]).join(" ")
    ldflags = (["-flto"] + lto[:cflags] + lto[:ldflags]).join(" ")
    env = "CARGO_TARGET_#{lto[:host].upcase.tr("-", "_")}_RUSTFLAGS"
    warnflags = MMTkLTO.filter_warnflags(lto[:cc], $warnflags).join(" ")
    conf << <<~MAKEFILE
      MMTK_CLEAN_DIRS = #{lto[:host]}

      ifeq ($(MMTK_BUILD), release)
      CC = #{cc}
      CFLAGS += #{cflags}
      DLDFLAGS += #{ldflags}
      warnflags = #{warnflags}
      MMTK_CARGO_ENV = #{env}="-Clinker-plugin-lto -C target-cpu=native"
      MMTK_CARGO_FLAGS = --target #{lto[:host]}
      MMTK_CARGO_FIXUP = mkdir -p release && cp -f #{lto[:host]}/release/$(LIBMMTK_RUBY) release/$(LIBMMTK_RUBY)
      endif
    MAKEFILE
  end

  conf
end
