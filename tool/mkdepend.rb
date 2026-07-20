#!ruby -s

# Update dependencies without a configured build or a C compiler:
#   ruby tool/mkdepend.rb -all -sources -inplace
# Expand source mappings into full dependencies:
#   ruby tool/mkdepend.rb -all -inplace
# Check committed source mappings without modifying files:
#   ruby tool/mkdepend.rb -all -sources -check
# The command can be run from either the source or a build directory.
#
# Dependency files can declare inputs that do not exist in the source tree:
#
#   # mkdepend: scan NAME => SOURCE
#     Scan SOURCE in place of a generated source or included header NAME.
#     `*` and `**` patterns are expanded from matching SOURCE files and
#     substituted into NAME.  Both sides must have the same pattern count.
#
#   # mkdepend: depends NAME => DEPENDENCY...
#     Associate NAME with dependencies.  They replace NAME when it is
#     included and are added when NAME is a source being scanned.  Make
#     A DEPENDENCY beginning with a Make variable reference is emitted
#     without path conversion.
#     `$(THREAD_MODEL)` in SOURCE is resolved as `pthread` by default.
#     When a thread model is supplied, it is resolved in SOURCE and
#     DEPENDENCY.
#
#   # mkdepend: define SOURCE => MACRO...
#   # mkdepend: undef SOURCE => MACRO...
#     Treat preprocessor MACROs as defined or undefined while scanning SOURCE.
#
# Declarations in the top-level depend file apply to all dependency files.
# A declaration in a more specific dependency file overrides one with the
# same name and kind.  An invalid `# mkdepend:` declaration is an error.

require 'set'
require 'tempfile'
require 'fileutils'

TOP_SRCDIR = File.expand_path("..", __dir__)

class Mkdepend
  Declarations = Struct.new(
    :scan, :dependencies, :defines, :undefines,
  )
end

class Mkdepend::Scanner
  attr_reader :unresolved

  def initialize(root:, include_dirs:, quote_dirs: [], macros: {},
                 targets: [], aliases: {}, dependencies: {}, defined: [],
                 undefined: [])
    @root = File.expand_path(root)
    @include_dirs = include_dirs.map {|dir| File.expand_path(dir, @root)}
    @quote_dirs = quote_dirs.map {|dir| File.expand_path(dir, @root)}
    @macros = macros
    @targets = targets.to_set
    @aliases = aliases
    @dependencies = dependencies
    @defined = defined.to_set
    @undefined = undefined.to_set
    @unresolved = Set.new
  end

  def scan(source)
    dependencies = Set.new
    visit(File.expand_path(source, @root), dependencies, Set.new)
    dependencies.to_a.sort
  end

  private

  def visit(path, dependencies, visited, record: true)
    path = File.expand_path(path)
    return unless File.file?(path)
    return if visited.include?(path)
    visited.add(path)
    dependencies.add(relative(path)) if record

    conditions = []
    File.open(path, "rb") do |file|
      file.each_line do |line|
        directive = line[/\A\s*#\s*(.*)/, 1]
        next unless directive

        case directive
        when /\Aifdef\s+(\w+)/
          conditions << symbol_condition($1)
        when /\Aifndef\s+(\w+)/
          condition = symbol_condition($1)
          conditions << (condition == :all ? :all : !condition)
        when /\Aif\s+(.+)/
          conditions << expression_condition($1)
        when /\Aelif\s+(.+)/
          conditions[-1] = if conditions[-1] == true
            false
          elsif conditions[-1] == false
            expression_condition($1)
          else
            :all
          end
        when /\Aelse\b/
          conditions[-1] = !conditions[-1] if [true, false].include?(conditions[-1])
        when /\Aendif\b/
          conditions.pop
        else
          next if conditions.include?(false)
          case directive
          when /\A(?:line\s+)?\d+\s+"([^"<>]+)"/
            dependencies.add($1.delete_prefix("./"))
          when /\Ainclude(?:_next)?\s+(.+)/
            scan_include($1, path, dependencies, visited)
          end
        end
      end
    end
  end

  def symbol_condition(symbol)
    return true if @defined.include?(symbol)
    return false if @undefined.include?(symbol)
    :all
  end

  def expression_condition(expression)
    case expression.sub(%r{/\*.*}, '').strip
    when /\A0+[LU]*(?:\z|\s*&&)/i
      return false
    when /\A1+[LU]*(?:\z|\s*\|\|)/i
      return true
    when /\A(!?)\s*defined\s*(?:\(\s*)?(\w+)/
      condition = symbol_condition($2)
      return condition if condition == :all
      return $1.empty? ? condition : !condition
    when /\A(!?)(\w+)\z/
      condition = symbol_condition($2)
      return condition if condition == :all
      return $1.empty? ? condition : !condition
    end
    :all
  end

  def scan_include(argument, current, dependencies, visited)
    case argument.sub(%r{//.*\z}, '').strip
    when /\A([<"])([^>"]+)[>"]/
      quoted = $1 == '"'
      name = $2
    when /\A([A-Za-z_]\w*)/
      name = $1
      unless @aliases.key?(name) || @dependencies.key?(name) ||
          @targets.include?(name)
        name = @macros[name]
      end
      quoted = true
    end
    return unless name

    if alias_path = @aliases[name]
      if virtual = @dependencies[name]
        dependencies.merge(virtual)
      else
        dependencies.add(name)
      end
      visit(File.expand_path(alias_path, @root), dependencies, visited, record: false)
      return
    end

    if virtual = @dependencies[name]
      dependencies.merge(virtual)
    elsif name.end_with?(".inc", ".rbinc", ".rbbin")
      dependencies.add(name)
    elsif path = resolve(name, current, quoted)
      visit(path, dependencies, visited)
    elsif @targets.include?(name)
      dependencies.add(name)
    else
      @unresolved.add(name)
    end
  end

  def resolve(name, current, quoted)
    dirs = []
    dirs << File.dirname(current) if quoted
    dirs.concat(@quote_dirs) if quoted
    dirs.concat(@include_dirs)
    dirs.each do |dir|
      path = File.expand_path(name, dir)
      return path if File.file?(path)
    end
    nil
  end

  def relative(path)
    prefix = @root + File::SEPARATOR
    path.start_with?(prefix) ? path.delete_prefix(prefix) : path
  end
end

class Mkdepend
  attr_reader :root

  def initialize(root: TOP_SRCDIR, thread_model: nil)
    @root = File.expand_path(root)
    @thread_model = thread_model
    @dependency_declarations = {}
    @dependency_targets = {}
    @dependency_contents = {}
  end

  def expand_scan_declaration(name, source)
    source_parts = source.split(/(\*\*|\*)/)
    captures = source_parts.count {|part| part == "*" || part == "**"}
    return unless captures == name.scan(/\*\*|\*/).size
    return {name => source} if captures.zero?

    pattern = source_parts.map do |part|
      case part
      when "**" then "(.*)"
      when "*" then "([^/]*)"
      else Regexp.escape(part)
      end
    end.join
    pattern = /\A#{pattern}\z/
    Dir.glob(File.join(@root, source)).sort.each_with_object({}) do |path, map|
      path = relative_source(path)
      match = pattern.match(path) or next
      values = match.captures
      generated = name.gsub(/\*\*|\*/) {values.shift}
      map[generated] = path
    end
  end

  def parse_dependency_declarations(path, content = nil)
    declarations = Declarations.new({}, {}, {}, {})
    content ||= File.read(path) if File.file?(path)
    return declarations unless content

    lineno = 0
    content.each_line do |line|
      lineno += 1
      case line[/\A#\s*mkdepend:\s*\K.*/]
      when nil
        next
      when /\Ascan\s+(\S+)\s*=>\s*(\S+)\s*\z/
        scan = expand_scan_declaration($1, $2)
        unless scan && (!scan.empty? || !$2.include?("*"))
          raise "#{path}:#{lineno}: invalid mkdepend declaration: #{line.strip}"
        end
        declarations.scan.update(scan)
      when /\Adepends\s+(\S+)\s*=>\s*(.+?)\s*\z/
        name, dependencies = $1, $2.split
        if declarations.dependencies.key?(name)
          raise "#{path}:#{lineno}: duplicate mkdepend declaration: #{name}"
        end
        declarations.dependencies[name] = dependencies
      when /\Adefine\s+(\S+)\s*=>\s*(.+?)\s*\z/
        declarations.defines[$1] = $2.split
      when /\Aundef\s+(\S+)\s*=>\s*(.+?)\s*\z/
        declarations.undefines[$1] = $2.split
      else
        raise "#{path}:#{lineno}: invalid mkdepend declaration: #{line.strip}"
      end
    end
    declarations.scan.transform_values! do |source|
      source.gsub('$(THREAD_MODEL)', @thread_model || 'pthread')
    end
    if @thread_model
      declarations.dependencies.transform_values! do |dependencies|
        dependencies.map do |dependency|
          dependency.gsub('$(THREAD_MODEL)', @thread_model)
        end
      end
    end
    declarations
  end

  def dependency_file_content(path, content = nil)
    path = File.expand_path(path, @root)
    if content
      @dependency_contents[path] = content
    elsif @dependency_contents.key?(path)
      @dependency_contents[path]
    elsif File.file?(path)
      @dependency_contents[path] = File.read(path)
    end
  end

  def dependency_declarations(input = nil, source: nil, content: nil)
    input ||= dependency_input(source)
    input = relative_source(input || "depend")
    @dependency_declarations[input] ||= begin
      if input == "depend"
        path = File.join(@root, input)
        parse_dependency_declarations(path, dependency_file_content(path, content))
      else
        global = dependency_declarations("depend")
        path = File.absolute_path?(input) ? input : File.join(@root, input)
        local = parse_dependency_declarations(
          path, dependency_file_content(path, content),
        )
        Declarations.new(
          global.scan.merge(local.scan),
          global.dependencies.merge(local.dependencies),
          global.defines.merge(local.defines),
          global.undefines.merge(local.undefines),
        )
      end
    end
  end

  def dependency_input(source)
    return "depend" unless source
    source = relative_source(source)
    if source.start_with?("ext/")
      dir = File.dirname(source)
      until dir == "." || dir == "ext"
        return File.join(dir, "depend") if File.file?(File.join(@root, dir, "depend"))
        dir = File.dirname(dir)
      end
    elsif source.start_with?("enc/")
      return "enc/depend"
    end
    "depend"
  end

  def declaration(map, name, input = nil)
    candidates = [name]
    if input
      dir = File.dirname(relative_source(input))
      candidates << name.delete_prefix(dir + "/") unless dir == "."
    end
    key = candidates.uniq.find {|candidate| map.key?(candidate)}
    [key, map[key]] if key
  end

  def dependency_targets(input, content = nil)
    input = relative_source(input)
    @dependency_targets[input] ||= begin
      targets = []
      path = File.absolute_path?(input) ? input : File.join(@root, input)
      content = dependency_file_content(path, content)
      if content
        content.each_line do |line|
          if line.start_with?(MARK_START)..line.start_with?(MARK_END)
            next
          elsif target = line[/\A[^\s#][^:=]*?(?=\s*:(?!=))/]
            targets.concat(target.split)
          end
        end
      end
      targets.uniq
    end
  end

  def dependency_target(name, input)
    input = relative_source(input)
    targets = dependency_targets(input)
    candidates = [name]
    dir = File.dirname(input)
    candidates << name.delete_prefix(dir + "/") unless dir == "."
    candidates.uniq.find {|candidate| targets.include?(candidate)}
  end

  def relative_source(path)
    expanded = File.expand_path(path)
    expanded = File.expand_path(path, @root) unless File.exist?(expanded)
    prefix = @root + File::SEPARATOR
    expanded.start_with?(prefix) ? expanded.delete_prefix(prefix) : path
  end

  def extension_dependency(file, source_dir)
    case file
    when %r[\A(?:#{Regexp.escape(source_dir)}/)?extconf\.h\z]
      "$(RUBY_EXTCONF_H)"
    when 'config.h'
      "$(arch_hdrdir)/ruby/config.h"
    when %r[\Ainclude/]
      "$(hdrdir)/#$'"
    when 'probes.h'
    else
      if file.start_with?(prefix = source_dir + "/")
        file.delete_prefix(prefix)
      elsif file.start_with?(prefix = File.dirname(source_dir) + "/")
        "$(srcdir)/../#{file.delete_prefix(prefix)}"
      elsif !file.include?("/") && File.file?(File.join(@root, source_dir, file))
        file
      elsif /\.e?rb\z/.match?(file)
        nil
      else
        "$(top_srcdir)/#{file}"
      end
    end
  end

  def depends(files, vpath, source: nil, input: nil, declarations: nil)
    declaration_input = input || dependency_input(source)
    declarations ||= dependency_declarations(declaration_input, source: source)
    extension_dir = File.dirname(source) if source&.start_with?("ext/")
    expand = lambda do |file, expanded|
      if !expanded.include?(file) &&
          (dependencies = declaration(declarations.dependencies, file,
                                      declaration_input))
        dependencies[1].flat_map {|dep| expand.call(dep, expanded | [file])}
      else
        file
      end
    end
    files = files.flat_map {|file| expand.call(file, [])}
    files.each_with_object([]) do |file, deps|
      file = relative_source(file)
      dep = if file.start_with?('$(', '{$(')
        file
      elsif target = dependency_target(file, declaration_input)
        target
      elsif extension_dir
        extension_dependency(file, extension_dir)
      else
        case file
        when %r[\Aenc/unicode/[\d.]+/]
          "$(UNICODE_HDR_DIR)/#$'"
        when 'encindex.h', 'transcode_data.h', /\Areg(?!ex\b)\w+\.h\z/
          "#{vpath || '$(top_srcdir)/'}#{file}"
        when /\.e?rb\z/
        when %r[\Atool/]
          "$(top_srcdir)/#{file}"
        when %r[\Ainclude/\Kruby(?:/ruby|/version)?\.h\z]
          "$(hdrdir)/#$&"
        when %r[\A(?:internal|prism)\/]
          "$(top_srcdir)/#{file}"
        when %r[\Accan/]
          "$(CCAN_DIR)/#$'"
        when %r[\Aenc/]
          "#{vpath}#{file}"
        when %r[\Ainclude/ruby/], %r[\Amissing/]
          "#{vpath}#$'"
        else
          "#{vpath}#{file}"
        end
      end
      deps << dep if dep
    end.uniq.sort
  end

  def object_name(src)
    stem = src.sub(/\.[cy]\z/, "")
    if src.start_with?("ext/")
      "#{File.basename(stem)}.o"
    else
      "#{stem.delete_prefix('missing/')}.$(OBJEXT)"
    end
  end

  def dependency_vpath(input, source)
    return if source.start_with?("enc/") &&
      (!input || relative_source(input) == "enc/depend")
    "{$(VPATH)}"
  end

  def dependency_source?(source, input = nil)
    declarations = dependency_declarations(input, source: source)
    declaration(declarations.scan, source, input) ||
      declaration(declarations.dependencies, source, input) ||
      dependency_target(source, input || dependency_input(source))
  end

  def dependency_scanner(src, declarations, input)
    macros = {}
    macros["RUBY_EXTCONF_H"] = "extconf.h" if src.start_with?("ext/")
    defined = declaration(declarations.defines, src, input)&.last || []
    undefined = %w[__cplusplus]
    if undefined_macros = declaration(declarations.undefines, src, input)
      undefined.concat(undefined_macros[1])
    end
    Scanner.new(
      root: @root,
      include_dirs: [
        @root,
        File.join(@root, "include"),
        File.join(@root, "prism"),
        File.dirname(src),
      ],
      macros: macros,
      targets: dependency_targets(input),
      aliases: declarations.scan,
      dependencies: declarations.dependencies,
      defined: defined,
      undefined: undefined,
    )
  end

  def makedepend(src, out = [], target: nil, input: nil)
    src = relative_source(src)
    declaration_input = input || dependency_input(src)
    declarations = dependency_declarations(declaration_input, source: src)
    vpath = dependency_vpath(input, src)
    scanner = dependency_scanner(src, declarations, declaration_input)
    scan_source = if mapping = declaration(declarations.scan, src,
                                           declaration_input)
      mapping[1]
    else
      src
    end
    files = scanner.scan(scan_source)
    if dependencies = declaration(declarations.dependencies, src,
                                  declaration_input)
      files.concat(dependencies[1])
    end
    files << src if scan_source != src
    files << src.sub(/\.y\z/, ".c") if src.end_with?(".y")
    obj = if target
      src.start_with?("ext/") ? "#{target}.o" : "#{target}.$(OBJEXT)"
    else
      object_name(src)
    end
    depends(files, vpath, source: src, input: input,
            declarations: declarations).each do |dep|
      out << "#{obj}: #{dep}\n"
    end
    out
  end

  def compact_dependencies(rules, group: true)
    return rules.lines.uniq.sort.join unless group

    grouped = Hash.new {|hash, dependency| hash[dependency] = []}
    lines = []
    rules.each_line do |line|
      unless /\A(\S+):\s+(\S+)\s*\z/ =~ line
        lines << line
        next
      end
      target, dependency = $1, $2
      if dependency.end_with?(".c", ".y")
        lines << "#{target}: #{dependency}\n"
      else
        grouped[dependency] << target
      end
    end
    grouped.each do |dependency, targets|
      targets.uniq.sort.each_slice(8) do |slice|
        lines << "#{slice.join(' ')}: #{dependency}\n"
      end
    end
    lines.uniq.sort.join
  end

  def normalize_dependency_rules(rules)
    rules.gsub('{$(VPATH)}', '')
  end

  def same_dependency_rules?(left, right)
    normalize_dependency_rules(left) == normalize_dependency_rules(right)
  end

  MARK_START = "# AUTOGENERATED DEPENDENCIES START"
  MARK_END = "# AUTOGENERATED DEPENDENCIES END"
  MARK_SECTION =
    /^#{Regexp.escape(MARK_START)}[^\S\n]*(?:\z|\n\K(?m:.*?)(?=(^#{Regexp.escape(MARK_END)}(?:\n|\z))|\z))/

  def dependency_files(scope = :all)
    Dir.chdir(@root) do
      files = case scope
      when :all
        %w[depend enc/depend].concat(Dir.glob("ext/**/depend"))
      when :core
        %w[depend enc/depend]
      when :extensions
        Dir.glob("ext/**/depend")
      else
        raise ArgumentError, "unknown dependency scope: #{scope}"
      end
      files.select do |file|
        next false unless File.file?(file)
        content = File.read(file)
        next false unless content.include?(MARK_START)
        dependency_file_content(file, content)
        true
      end
    end
  end

  def dependency_source_rules(rules, input)
    input = relative_source(input)
    srcs = {}
    rules.each_line do |line|
      next unless %r[\A([-.\w/]+)\.(?:\$\(OBJEXT\)|o):\s+(.+?)\s*\z] =~ line
      target, dependency = $1, $2
      next unless src = dependency[%r{[-.\w/]+\.[cy]\z}]
      src = src.delete_prefix("/")
      source_name = File.basename(src, ".*")
      target_name = File.basename(target)
      next unless target_name == source_name || target_name.end_with?("-#{source_name}")
      local = input.start_with?("ext/") && !dependency.include?("$(top_srcdir)")
      src = File.join(File.dirname(input), src) if local && !src.start_with?("ext/")
      rank = src.end_with?(".y") ? 2 : local ? 1 : 0
      current = srcs[target]
      srcs[target] = [rank, src, line] if !current || rank >= current.first
    end
    srcs.sort.to_h
  end

  def dependency_source_map(rules, input)
    dependency_source_rules(rules, input).each_with_object({}) do |(target, data), result|
      result[target] = data[1]
    end
  end

  def dependency_sources(rules, input)
    dependency_source_map(rules, input).values
  end

  def resolve_dependency_source(src, input)
    return src if File.file?(File.join(@root, src))

    missing = "missing/#{src}"
    return missing if File.file?(File.join(@root, missing))
    return src if dependency_source?(src, input)

    raise "source file not found: #{src} in #{input}"
  end

  def minimize_deps(rules, input)
    sources = dependency_source_rules(rules, input)
    targets = rules.scan(%r[^([-\.\w/]+)\.(?:\$\(OBJEXT\)|o):]).flatten.uniq
    unless (missing = targets - sources.keys).empty?
      raise "no source files for #{missing.join(', ')} in #{input}"
    end
    sources.each_value {|_, src| resolve_dependency_source(src, input)}
    sources.values.map(&:last).uniq.sort.join
  end

  def update_deps(rules, input, group: true)
    sources = dependency_source_map(rules, input)
    targets = rules.scan(%r[^([-.\w/]+)\.(?:\$\(OBJEXT\)|o):]).flatten.uniq
    unless (missing = targets - sources.keys).empty?
      raise "no source files for #{missing.join(', ')} in #{input}"
    end
    generated = []
    sources.each do |target, src|
      src = resolve_dependency_source(src, input)
      warn "dependencies for #{src}:" if $verbose
      makedepend(src, generated, target: target, input: input)
    end
    compact_dependencies(generated.join, group: group)
  end

  def replace_file(path, content)
    dir = File.dirname(path)
    FileUtils.mkdir_p(dir)
    mode = File.exist?(path) ? File.stat(path).mode & 0777 : 0644
    Tempfile.create([File.basename(path), ".tmp"], dir) do |file|
      file.binmode
      file.write(content)
      file.flush
      file.chmod(mode)
      file.close
      File.rename(file.path, path)
    end
  end

  def report_outdated_dependencies(input, current, expected, err: $stderr)
    current_lines = current.lines
    expected_lines = expected.lines
    label = relative_source(input)
    err.puts "#{label}: dependencies are outdated"
    if current_lines.size <= 20
      err.puts "  current dependency rules:"
      current_lines.each {|line| err.puts "    #{line.chomp}"}
    else
      current_word = current_lines.one? ? "rule" : "rules"
      expected_word = expected_lines.one? ? "source rule" : "source rules"
      err.puts "  current section has #{current_lines.size} #{current_word}; " \
               "expected #{expected_lines.size} #{expected_word}"
    end
    err.puts "  expected source rules:"
    expected_lines.each {|line| err.puts "    #{line.chomp}"}
  end

  def run(inputs = ARGV, out: $stdout, err: $stderr, output: $output,
          nmake: $nmake, sources: $sources, inplace: $inplace,
          check: $check,
          scope: ($core ? :core :
                  $extensions ? :extensions :
                  $all ? :all : nil))
    if scope
      inputs = dependency_files(scope).map {|file| File.join(@root, file)}
    end
    output = File.expand_path(output) if output
    changed = false
    inputs.each do |input|
      if input.end_with?(".c", ".y")
        out.puts makedepend(input)
      else
        deps = dependency_file_content(input) || File.read(input)
        dependency_declarations(input, content: deps)
        dependency_targets(input, deps)
        match = MARK_SECTION.match(deps)
        next unless match
        raise "missing #{MARK_END} in #{input}" unless match.begin(1)

        current_rules = match[0]
        expected = if sources
          minimize_deps(current_rules, input)
        else
          update_deps(current_rules, input, group: !nmake)
        end
        updated = match.pre_match + expected + match.post_match
        if output
          updated = normalize_dependency_rules(updated) unless nmake
          replace_file(File.join(output, relative_source(input)), updated)
        elsif same_dependency_rules?(current_rules, expected)
          next
        elsif inplace
          replace_file(input, updated)
          changed = true
        elsif check
          report_outdated_dependencies(input, current_rules, expected, err: err)
          changed = true
        else
          out.puts updated
          changed = true
        end
      end
    end
    if check && changed
      options = " -sources" if sources
      err.puts "\nupdate with:"
      err.puts "  ruby tool/mkdepend.rb -all#{options} -inplace"
    end
    !changed | output
  end
end

if __FILE__ == $0
  success = Mkdepend.new(
    root: $root || TOP_SRCDIR,
    thread_model: $thread_model,
  ).run
  exit(false) if $check && !success
end
