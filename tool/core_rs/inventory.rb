#!/usr/bin/env ruby
# frozen_string_literal: true
#
# tool/core_rs/inventory.rb: exact function inventory of the CRuby C core,
# wave classification, port units and port-kit issue bodies.
#
#   ruby tool/core_rs/inventory.rb                    # summary by wave
#   ruby tool/core_rs/inventory.rb --list [--wave A] [--file st.c] [--format tsv|json]
#   ruby tool/core_rs/inventory.rb --units [--wave A] [--open]
#   ruby tool/core_rs/inventory.rb --kit st-A-03       # port-kit issue body (Markdown)
#   ruby tool/core_rs/inventory.rb --check            # C guards vs Rust exports
#   ruby tool/core_rs/inventory.rb --snapshot         # dump full TSV snapshot
#
# Standard Ruby library only.  Paths resolve relative to this file.
#
# Scope: the top-level *.c files of the interpreter, plus the missing/*.c
# files they compile in with #include (dtoa, mt19937).  A definition is a
# function whose name is followed by `(` at file scope and whose body opens
# before any `;` (CRuby style: the closing brace is at column 0).  When a
# function has several #if variants in one file it is counted once.
#
# Waves (docs: docs/ruby_on_rust/migration-strategy.md, decisions D2/D3):
#   A  leaf: the definition never mentions Ruby objects (VALUE, ID, Qnil,
#      raising, the VM).  Can be fuzzed as pure functions.
#   B  public C API (declared in include/ruby/) that uses objects only
#      through the C API, never through internal struct layouts.
#   C  everything else outside wave D: internals that need struct layouts,
#      write barriers or VM state.  Phase 2.
#   D  out of Phase 1 by decision D3: Onigmo (reg*.c), the compilers and
#      parser glue, the VM, GC and JIT glue.
#   X  not part of the library: entry points and build stubs.
#
# A function is "ported" when its C definition sits inside an
# `#if !USE_RUST_PORTS` block (AGENTS.md §6.4).

require "optparse"
require "json"

SRCDIR = File.expand_path("../..", __dir__)

WAVE_D = /\A(reg\w*|compile|parse|parse_\w+|prism_compile|prism_init|vm|vm_\w+|gc|ast|node|node_dump|parser_st|ruby_parser|universal_parser|jit|yjit|zjit|iseq|builtin|mini_builtin)\.c\z/
WAVE_X = /\A(main|goruby|ruby-runner|rubystub|dmydln|dmyenc|dmyext|miniinit|inits|debug_counter|sparc)\.c\z/

# Tokens that mean a definition touches Ruby objects or VM state.
OBJECT_TOKENS = /\b(?:VALUE|ID|Q(?:nil|true|false|undef)|rb_raise\w*|rb_exc_\w+|rb_sys_fail\w*|rb_syserr\w*|rb_warn\w*|rb_warning\w*|rb_funcall\w*|rb_yield\w*|rb_ensure|rb_protect|rb_rescue\w*|rb_jump_tag|rb_gc\w*|rb_execution_context_t|rb_thread_t|rb_vm_t|rb_iseq_t|rb_control_frame_t|GET_EC|GET_VM|GET_THREAD|GET_RACTOR|RB_VM_LOCK\w*|ruby_xmalloc\w*|ruby_xfree|xmalloc\w*|xfree|ALLOC\w*|ZALLOC\w*|rb_memerror)\b/
# Tokens that mean a definition reads object internals directly.
STRUCT_TOKENS = /\b(?:R(?:STRING|ARRAY|HASH|BASIC|OBJECT|CLASS|MODULE|STRUCT|TYPEDDATA|DATA|FLOAT|BIGNUM|RATIONAL|COMPLEX|REGEXP|FILE|MATCH|SYMBOL)\s*\(|FL_(?:SET|UNSET|TEST)\w*|RB_FL_\w+|RB_OBJ_WRITE\w*|RBASIC_\w+|STR_EMBED\w*|ARY_EMBED\w*|ARY_HEAP\w*|RCLASS_\w+|ROBJECT_\w+|RHASH_\w+|RB_SPECIAL_CONST_P|BIGNUM_\w+|RSTRUCT_\w+|rb_shape\w*|imemo\w*|ENC_CODERANGE\w*)|->(?:flags|klass|as)\b/

Func = Struct.new(:file, :name, :first, :last, :loc, :static, :public, :ported, :variants, :wave, :callees, :body, keyword_init: true) do
  def range = "#{first}-#{last}"
  def to_h = super.reject { |k, _| k == :callees || k == :body }.merge(range: range)
end

# ---- public API from include/ruby ----------------------------------------

def public_names
  names = {}
  aliases = {}
  Dir[File.join(SRCDIR, "include/ruby/**/*.h")].each do |h|
    state = { in_comment: false }
    File.readlines(h, encoding: "binary").each do |line|
      if line =~ /^#\s*define\s+(\w+)\s+(rb_\w+|ruby_\w+)\s*$/
        aliases[$1] = $2
        next
      end
      next if line =~ /^\s*#/
      # Every identifier called or declared outside the preprocessor: the
      # prototypes, and the functions the public inline functions call.
      strip_comments(line, state).first.scan(/\b([A-Za-z_]\w*)\s*\(/) { |n,| names[n] = true }
    end
  end
  [names, aliases]
end

# ---- parsing C files -------------------------------------------------------

def strip_comments(line, state)
  out = +""
  i = 0
  while i < line.size
    if state[:in_comment]
      j = line.index("*/", i)
      return [out, state] unless j
      state[:in_comment] = false
      i = j + 2
    elsif line[i, 2] == "/*"
      state[:in_comment] = true
      i += 2
    elsif line[i, 2] == "//"
      break
    elsif line[i] == '"' || line[i] == "'"
      q = line[i]
      j = i + 1
      j += (line[j] == "\\" ? 2 : 1) while j < line.size && line[j] != q
      out << q << q
      i = j + 1
    else
      out << line[i]
      i += 1
    end
  end
  [out, state]
end

def scan_file(path, pub, aliases)
  file = path.delete_prefix(SRCDIR + "/")
  raw = File.readlines(path, encoding: "binary")
  state = { in_comment: false }
  code = raw.map { |l| strip_comments(l, state).first }
  funcs = {}
  cond = [] # one entry per open #if: true when it is `#if !USE_RUST_PORTS`
  i = 0
  while i < code.size
    line = code[i]
    if line =~ /\A\s*#\s*(if|ifdef|ifndef|elif|else|endif)\b(.*)/
      kw, rest = $1, $2
      case kw
      when "if", "ifdef", "ifndef" then cond.push(kw == "if" && rest =~ /\A\s*!\s*USE_RUST_PORTS\b/ ? true : false)
      when "elif", "else" then cond[-1] = false unless cond.empty?
      when "endif" then cond.pop
      end
      i += 1
      next
    end
    if line =~ /\A(?:[A-Za-z_][\w\s\*]*?[\s\*])?([A-Za-z_]\w*)\s*\(/ && !line.start_with?(" ", "\t", "#") &&
       !%w[if for while switch return sizeof defined].include?($1)
      name = $1
      # Collect until `{` or `;` at file scope.
      text = +""
      j = i
      while j < code.size && j < i + 40
        text << code[j]
        break if text =~ /[{;]/
        j += 1
      end
      brace = text.index("{")
      semi = text.index(";")
      eq = text.index("=")
      if brace && (!semi || brace < semi) && !(eq && eq < (text.index("(") || 0)) &&
         text[0...brace] =~ /\)\s*(?:\w+\b\s*(?:\([^)]*\)\s*)?)*\z/m
        last = (j...code.size).find { |k| raw[k].start_with?("}") }
        if last
          head = (i > 0 ? code[i - 1] : "") + line
          body = code[i..last].join
          static = head =~ /\bstatic\b/ ? true : false
          if (f = funcs[name])
            f.variants += 1
          else
            ported = cond.include?(true)
            is_pub = !static && (pub[name] || pub[aliases[name]]) ? true : false
            funcs[name] = Func.new(file: file, name: name, first: i + 1, last: last + 1,
                                   loc: last - i + 1, static: static, public: is_pub,
                                   ported: ported, variants: 1, wave: classify(file, body, is_pub),
                                   callees: body.scan(/\b([A-Za-z_]\w*)\s*\(/).flatten.uniq, body: body)
          end
          i = last + 1
          next
        end
      end
    end
    i += 1
  end
  funcs.values
end

def classify(file, body, is_pub)
  return "X" if file =~ WAVE_X
  return "D" if file =~ WAVE_D
  return "A" unless body =~ OBJECT_TOKENS
  return "B" if is_pub && body !~ STRUCT_TOKENS
  "C"
end

def inventory
  pub, aliases = public_names
  paths = Dir[File.join(SRCDIR, "*.c")].sort
  if !paths.empty? && system("git", "rev-parse", "--is-inside-work-tree", out: File::NULL, err: File::NULL, chdir: SRCDIR)
    IO.popen(["git", "-C", SRCDIR, "check-ignore", *paths]) do |io|
      ignored = io.read.split("\n")
      paths -= ignored
    end
  end
  # missing/*.c sources that a core file compiles in with #include
  # (missing/dtoa.c in util.c, missing/mt19937.c in random.c).
  included = paths.reject { |p| File.basename(p) =~ WAVE_D || File.basename(p) =~ WAVE_X }.flat_map do |p|
    File.read(p, encoding: "binary").scan(/^#\s*include\s+"(missing\/\w+\.c)"/).flatten.map { |m| File.join(SRCDIR, m) }
  end
  funcs = (paths + included.uniq).flat_map { |p| scan_file(p, pub, aliases) }
  demote_non_leaves(funcs)
  funcs
end

# A leaf must not reach Ruby objects through its callees either: a Wave A
# function that calls a function of another wave is not a leaf.  Callees
# resolve to a static function of the same file first, then to any
# non-static definition.  Repeat until nothing changes.
def demote_non_leaves(funcs)
  global = {}
  funcs.each { |f| global[f.name] ||= f unless f.static }
  local = funcs.group_by(&:file).transform_values { |fs| fs.to_h { |f| [f.name, f] } }
  loop do
    changed = false
    funcs.each do |f|
      next unless f.wave == "A"
      bad = f.callees.find do |c|
        next false if c == f.name
        g = local[f.file][c] || global[c]
        g && g.wave != "A"
      end
      next unless bad
      f.wave = f.public && f.body !~ STRUCT_TOKENS ? "B" : "C"
      changed = true
    end
    break unless changed
  end
  funcs.each { |f| f.body = nil } # callees stay: --check uses them
end

# ---- port units --------------------------------------------------------------

UNIT_MAX_FUNCS = 12
UNIT_MAX_LOC = 400

# Functions of one wave in one file that call each other (directly or
# through each other) always share a unit, so a static helper is ported
# together with its callers and can stay private to the Rust module.
# Those call clusters are packed in source order into units of at most
# UNIT_MAX_FUNCS functions and UNIT_MAX_LOC lines (a larger cluster is
# split in source order).  Ported functions stay in their unit, so unit ids are
# stable while ports land.
def units(funcs)
  out = []
  funcs.group_by(&:file).each do |file, fs|
    base = File.basename(file, ".c")
    fs.group_by(&:wave).each do |wave, wfs|
      next if %w[D X].include?(wave)
      by_name = wfs.to_h { |f| [f.name, f] }
      parent = wfs.to_h { |f| [f.name, f.name] }
      find = ->(x) { x = parent[x] while parent[x] != x; x }
      wfs.each do |f|
        (f.callees || []).each do |c|
          next unless by_name[c]
          ra, rb = find.(f.name), find.(c)
          parent[ra] = rb if ra != rb
        end
      end
      clusters = wfs.group_by { |f| find.(f.name) }.values.map { |c| c.sort_by(&:first) }.sort_by { |c| c.first.first }
      cur = []
      n = 0
      flush = lambda do
        next if cur.empty?
        n += 1
        out << { id: format("%s-%s-%02d", base, wave, n), file: file, wave: wave, funcs: cur.sort_by(&:first) }
        cur = []
      end
      clusters.each do |c|
        if !cur.empty? && (cur.size + c.size > UNIT_MAX_FUNCS || cur.sum(&:loc) + c.sum(&:loc) > UNIT_MAX_LOC)
          flush.call
        end
        if c.size > UNIT_MAX_FUNCS || c.sum(&:loc) > UNIT_MAX_LOC
          # Too big for one unit: split in source order.  Helpers called
          # across the split are exported as rb_core_<file>_<name>.
          c.each do |f|
            flush.call if !cur.empty? && (cur.size >= UNIT_MAX_FUNCS || cur.sum(&:loc) + f.loc > UNIT_MAX_LOC)
            cur << f
          end
          flush.call
        else
          cur.concat(c)
        end
      end
      flush.call
    end
  end
  out
end

# ---- port kit -------------------------------------------------------------------

WAVE_B_RULES = <<~MD
  ### Ruby objects and exceptions (Wave B, AGENTS.md §6.9)
  - Use `crate::ffi` for `VALUE`, `Qnil`/`Qtrue`/`Qfalse`, `INT2FIX`/`FIX2LONG`, `RTEST` and the C API. If a public C API function you need is missing, add it to `core_rs/src/ffi/api.rs` with its prototype copied from `include/ruby/` (this file is in scope). Never declare internal functions.
  - Exception safety: no Rust frame may hold a `Drop` value across a call that can raise (`rb_raise`, `rb_funcallv`, conversions, allocation). If cleanup is needed, call the raising code through `ffi::protect::protect` and re-raise with `ffi::protect::jump_tag`, as the C does with `rb_protect`/`rb_jump_tag`.
  - Raise the same exception class with the same message at the same point as the C. The fuzz unit must compare raised exceptions too (run both sides under `rb_protect` and compare `rb_errinfo()` class and message).

MD

def kit(unit)
  file = unit[:file]
  mod = File.basename(file, ".c").tr("-", "_")
  todo = unit[:funcs].reject(&:ported)
  rows = unit[:funcs].map do |f|
    vis = f.public ? "public API" : (f.static ? "static" : "internal")
    "| `#{f.name}` | #{f.first}-#{f.last} | #{f.loc} | #{vis} | #{f.ported ? 'already ported' : 'to port'} |"
  end
  internal = todo.reject(&:public)
  <<~MD
    ## Port unit `#{unit[:id]}`: #{todo.size} function(s) from `#{file}` (Wave #{unit[:wave]})

    You are porting C functions of CRuby to Rust in `core_rs/`. Read **AGENTS.md §6–§12** first; they are binding. This issue is your whole task. Touch only the files listed under *Scope*.

    ### Functions
    Line ranges refer to `#{file}` on `master` at the time this issue was created. If a range is off, find the function by name; do not port anything else.

    | Function | Lines | LOC | Visibility | Status |
    |---|---|---|---|---|
    #{rows.join("\n")}

    ### Scope
    - `core_rs/src/#{mod}.rs`: the Rust ports. Create the file if needed, add `pub mod #{mod};` to `core_rs/src/lib.rs` and the file to `CORE_RS_SRCS` in `core_rs/core_rs.mk`.
    - `#{file}`: wrap **only** the definitions listed above in `#if !USE_RUST_PORTS` ... `#endif`, with a comment naming the Rust file (see `util.c`). Do not change the C itself.
    #{internal.empty? ? "" : "- `internal/core_rs.h` (create if missing): declarations for the non-public functions, which C now calls across the boundary. Exported Rust symbols must start with `rb_` (AGENTS.md §6.7). A static C function `foo` is exported as `rb_core_#{mod}_foo` and called through a `#define foo rb_core_#{mod}_foo` in the `#if USE_RUST_PORTS` branch. These symbols are hidden from `libruby.so` by core_rs's visibility control, so the export set stays unchanged.\n"}- `core_rs/fuzz/units/#{mod}_#{unit[:id].split('-').last}.c`: the differential fuzz unit (generate with `ruby tool/core_rs/inventory.rb --fuzz-unit #{unit[:id]}`).
    - `test/ruby/test_rust_ports.rb` or a new `test/ruby/test_rust_ports_#{mod}.rb`: Ruby-level tests reaching the ported functions. Add tests only; never edit existing ones.

    ### Fidelity rules (AGENTS.md §6.5)
    - Byte-for-byte the same behaviour as the C: return values, out-parameters, `errno`, wrapping arithmetic, `char` signedness, reads and writes. Same build-time macros honoured.
    - Safe Rust core functions over slices; `unsafe` only in the `extern "C"` wrappers, each with a `// SAFETY:` comment.
    - `no_std`, no allocation in Rust, no external crates, edition 2024, rustc 1.85.0 compatible.
    - No "safety improvements" (e.g. ignoring NULL): document the C precondition instead.
    - If the C reads past a buffer end, do not reproduce the overread; return the same result and say so in a comment, as `core_rs/src/re.rs` does.

    #{unit[:wave] == "B" ? WAVE_B_RULES : ""}### Required evidence (put it in the PR description, AGENTS.md §9)
    1. `make core-rs-test`: Rust unit tests that call the real functions (no `#[cfg(test)]` stubs).
    2. Differential fuzz, with both builds configured with `--enable-shared`, one of them also with `--without-rust-ports`:
       `ruby core_rs/fuzz/run.rb --with-ports ../build --without-ports ../build-noports core_rs/fuzz/units/<your unit>.c`
       must print `differential cases=1000000 mismatches=0` and a `MUTATION` line with mismatches > 0. Paste both lines.
    3. `make btest` and the affected `make test-all TESTS=...` suites in **both** builds.
    4. `nm -D --defined-only libruby.so | awk '{print $3}' | sort` is identical with and without your change.
    5. `ruby tool/generate_porting_ledger.rb --check` passes.
    6. `ruby tool/core_rs/inventory.rb --check` passes.

    ### Acceptance criteria
    - [ ] Every function marked "to port" is ported, and no other C is changed.
    - [ ] The fuzz unit covers every branch of every ported function; 0 mismatches over 1,000,000 cases; the mutation check passes.
    - [ ] Both build modes build and pass the tests above.
    - [ ] Export set unchanged; no change under `yjit/`, `zjit/`, `jit/`; no CI or test weakened.
    - [ ] The Port gate is green on the final commit.

    ### If you are blocked
    Do not guess and do not weaken anything. Comment on this issue (or your PR) with a line starting `BLOCKED:` that names the problem, what you tried, and the evidence (AGENTS.md §11). A port that cannot be made identical is a valid outcome: report it.
  MD
end

# ---- consistency check ------------------------------------------------------------

def extract_proto(lines, f)
  file = f.file
  name = f.name
  mod = File.basename(file, ".c").tr("-", "_")
  rs_name = f.static ? "rs_rb_core_#{mod}_#{name}" : "rs_#{name}"

  word = /(?<![\w])#{Regexp.escape(name)}\s*\(/
  start_idx = f.first - 1
  found_i = nil
  (start_idx..[start_idx + 10, lines.size - 1].min).each do |k|
    if lines[k] =~ word
      found_i = k
      break
    end
  end
  unless found_i
    (start_idx - 10..start_idx).reverse_each do |k|
      next if k < 0
      if lines[k] =~ word
        found_i = k
        break
      end
    end
  end
  i = found_i || start_idx

  text = +""
  j = i
  while j < lines.size
    text << lines[j]
    break if text.include?("{") || text.include?(";")
    j += 1
  end
  brace = text.index("{")
  semi = text.index(";")
  cut = brace && semi ? [brace, semi].min : (brace || semi)
  head = cut ? text[0...cut].strip : text.strip

  first = i
  while first > 0
    prev = lines[first - 1]
    break if prev.strip.empty? || prev.start_with?("#") ||
             prev.rstrip.end_with?(";", "}", "*/", "{") || prev.start_with?(" ", "\t")
    first -= 1
  end
  if first < i
    ret_prefix = lines[first...i].map(&:strip).join(" ")
    head = "#{ret_prefix} #{head}"
  end

  head = head.gsub(%r{/\*.*?\*/}m, "").gsub(%r{//.*$}, "").strip.gsub(/\s+/, " ")
  head = head.gsub(/\b(static|inline|extern|ALWAYS_INLINE|NOINLINE|PUREFUNC|RUBY_FUNC_EXPORTED|FUNC_FASTCALL)\b/, "").strip.gsub(/\s+/, " ")

  if head =~ /\A#{Regexp.escape(name)}\s*\(/
    head = "int " + head
  end

  if head =~ /(?<![\w])#{Regexp.escape(name)}\s*\(/
    head = head.sub(/(?<![\w])#{Regexp.escape(name)}\s*\(/, "#{rs_name}(")
  else
    head = "#{rs_name}()"
  end
  head.end_with?(";") ? head : "#{head};"
end

def fuzz_unit(unit)
  file = unit[:file]
  base_file = File.basename(file)
  mod = File.basename(file, ".c").tr("-", "_")
  unit_num = unit[:id].split("-").last
  unit_name = "#{mod}_#{unit_num}"

  path = File.join(SRCDIR, file)
  lines = File.exist?(path) ? File.readlines(path, encoding: "binary") : []

  func_names = unit[:funcs].map(&:name)
  extract_line = "FUZZ-EXTRACT: #{base_file} #{func_names.join(' ')}"

  protos = unit[:funcs].map { |f| extract_proto(lines, f) }

  <<~C
    /*
     * Differential fuzz unit for #{unit[:id]} (#{file}).
     * Generated by tool/core_rs/inventory.rb --fuzz-unit #{unit[:id]}.
     *
     * #{extract_line}
     */
    #define FUZZ_UNIT "#{unit_name}"
    #include "ruby/ruby.h"
    #include FUZZ_REF
    #include "fuzz.h"

    /* The Rust port of each function, declared with rs_ prefix. */
    #{protos.join("\n")}

    #define MAXLEN 64

    /* One random test case. Draw inputs that reach every branch, record them,
     * call both sides, and compare EVERY observable effect with FUZZ_EQ. */
    static void
    fuzz_one(void)
    {
        unsigned char buf[MAXLEN + 1];
        size_t len = fuzz_len(MAXLEN);
        const char *rs_in;

        fuzz_fill(buf, len, NULL);
        buf[len] = '\\0';
        fuzz_input("str", buf, len);
        rs_in = (const char *)fuzz_rs_bytes(buf, len);

        /* TODO: Exercise the ported functions and compare C vs Rust with FUZZ_EQ. */
    }
  C
end

# ---- consistency check ------------------------------------------------------------

def rust_exports
  Dir[File.join(SRCDIR, "core_rs/src/**/*.rs")].flat_map do |rs|
    File.read(rs, encoding: "UTF-8").scan(/#\[unsafe\(no_mangle\)\]\s*(?:#\[[^\]]*\]\s*)*pub\s+(?:unsafe\s+)?extern\s+"C"\s+fn\s+(\w+)/).flatten
  end
end

def check(funcs)
  errors = []
  exports = rust_exports
  ported = funcs.select(&:ported)
  ported.each do |f|
    if f.static
      # A ported static function needs an rb_core_<file>_<name> export only
      # while C code that is not ported still calls it.
      target = "rb_core_#{File.basename(f.file, '.c')}_#{f.name}"
      next if exports.include?(target)
      caller = funcs.find { |g| g.file == f.file && !g.ported && g.callees&.include?(f.name) }
      errors << "#{f.file}:#{f.first}: #{f.name} is ported but still called by #{caller.name} (#{f.file}:#{caller.first}); core_rs must export #{target}" if caller
    else
      errors << "#{f.file}:#{f.first}: #{f.name} is behind #if !USE_RUST_PORTS but core_rs exports no #{f.name}" unless exports.include?(f.name)
    end
  end
  exports.each do |e|
    errors << "core_rs exports #{e}, but no C definition of it is behind #if !USE_RUST_PORTS" unless
      ported.any? { |f| f.name == e || (f.static && e == "rb_core_#{File.basename(f.file, '.c')}_#{f.name}") }
  end
  errors
end

# ---- CLI ----------------------------------------------------------------------------

opts = { format: "tsv" }
OptionParser.new do |o|
  o.banner = "usage: #{$0} [--list|--units|--kit ID|--fuzz-unit ID|--check|--snapshot] [--wave W] [--file F] [--open] [--format tsv|json]"
  o.on("--list") { opts[:mode] = :list }
  o.on("--units") { opts[:mode] = :units }
  o.on("--kit ID") { |v| opts[:mode] = :kit; opts[:id] = v }
  o.on("--fuzz-unit ID") { |v| opts[:mode] = :fuzz_unit; opts[:id] = v }
  o.on("--check") { opts[:mode] = :check }
  o.on("--snapshot") { opts[:mode] = :snapshot }
  o.on("--wave W") { |v| opts[:wave] = v.upcase }
  o.on("--file F") { |v| opts[:file] = v }
  o.on("--open", "units with at least one function left to port") { opts[:open] = true }
  o.on("--format F") { |v| opts[:format] = v }
end.parse!

funcs = inventory
funcs = funcs.select { |f| f.file == opts[:file] } if opts[:file]

case opts[:mode]
when :snapshot
  puts %w[wave file name lines loc static public ported].join("\t")
  inventory.each { |f| puts [f.wave, f.file, f.name, f.range, f.loc, f.static, f.public, f.ported].join("\t") }
when :list
  sel = opts[:wave] ? funcs.select { |f| f.wave == opts[:wave] } : funcs
  if opts[:format] == "json"
    puts JSON.pretty_generate(sel.map(&:to_h))
  else
    puts %w[wave file name lines loc static public ported].join("\t")
    sel.each { |f| puts [f.wave, f.file, f.name, f.range, f.loc, f.static, f.public, f.ported].join("\t") }
  end
when :units
  us = units(funcs)
  us = us.select { |u| u[:wave] == opts[:wave] } if opts[:wave]
  us = us.select { |u| u[:funcs].any? { |f| !f.ported } } if opts[:open]
  puts %w[unit wave file functions to_port loc first last].join("\t")
  us.each do |u|
    puts [u[:id], u[:wave], u[:file], u[:funcs].size, u[:funcs].count { |f| !f.ported },
          u[:funcs].sum(&:loc), u[:funcs].first.first, u[:funcs].last.last].join("\t")
  end
when :kit
  u = units(inventory).find { |x| x[:id] == opts[:id] } or abort "no unit #{opts[:id]} (see --units)"
  puts kit(u)
when :fuzz_unit
  u = units(inventory).find { |x| x[:id] == opts[:id] } or abort "no unit #{opts[:id]} (see --units)"
  puts fuzz_unit(u)
when :check
  errs = check(inventory)
  errs.each { |e| warn e }
  puts errs.empty? ? "core_rs inventory check: OK" : "core_rs inventory check: #{errs.size} problem(s)"
  exit(errs.empty? ? 0 : 1)
else
  puts "Wave  Functions  LOC      Ported  Ported LOC  Public  Static"
  %w[A B C D X].each do |w|
    fs = funcs.select { |f| f.wave == w }
    p = fs.select(&:ported)
    printf("%-4s  %9d  %7d  %6d  %10d  %6d  %6d\n", w, fs.size, fs.sum(&:loc), p.size, p.sum(&:loc),
           fs.count(&:public), fs.count(&:static))
  end
  printf("all   %9d  %7d  %6d  %10d\n", funcs.size, funcs.sum(&:loc), funcs.count(&:ported), funcs.select(&:ported).sum(&:loc))
  puts
  puts "Phase 1 exit criteria (docs/ruby_on_rust/migration-strategy.md): Wave A >= 90% ported, Wave B >= 25% ported"
  { "A" => 0.90, "B" => 0.25 }.each do |w, goal|
    fs = funcs.select { |f| f.wave == w }
    done = fs.count(&:ported)
    need = (fs.size * goal).ceil
    printf("  Wave %s: %d / %d ported (%.1f%%), target %d: %s\n", w, done, fs.size, 100.0 * done / [fs.size, 1].max, need,
           done >= need ? "met" : "#{need - done} to go")
  end
end
