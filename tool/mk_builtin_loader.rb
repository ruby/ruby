# Parse built-in script and make rbinc file

require 'ripper'

def string_literal(lit, str = [])
  while lit
    case lit.first
    when :string_concat, :string_embexpr, :string_content
      _, *lit = lit
      lit.each {|s| string_literal(s, str)}
      return str
    when :string_literal
      _, lit = lit
    when :@tstring_content
      str << lit[1]
      return str
    else
      raise "unexpected #{lit.first}"
    end
  end
end

def inline_text argc, arg1
  raise "argc (#{argc}) of inline! should be 1" unless argc == 1
  arg1 = string_literal(arg1)
  raise "1st argument should be string literal" unless arg1
  arg1.join("").rstrip
end

def make_cfunc_name inlines, name, lineno
  case name
  when /\[\]/
    name = '_GETTER'
  when /\[\]=/
    name = '_SETTER'
  else
    name = name.tr('!?', 'EP')
  end

  base = "builtin_inline_#{name}_#{lineno}"
  if inlines[base]
    1000.times{|i|
      name = "#{base}_#{i}"
      return name unless inlines[name]
    }
    raise "too many functions in same line..."
  else
    base
  end
end

def collect_params tree
  while tree
    case tree.first
    when :params
      params = []
      _, mand, opt, rest, post, kwds, kwrest, block = tree
      mand.each {|_, v| params << v.to_sym} if mand
      opt.each {|(_, v), | params << v.to_sym} if opt
      params << rest[1][1].to_sym if rest
      post.each {|_, v| params << v.to_sym} if post
      params << kwrest[1][1].to_sym if kwrest
      params << block[1][1].to_sym if block
      return params
    when :paren
      tree = tree[1]
    else
      raise "unknown sexp: #{tree.first}"
    end
  end
end

def collect_builtin base, tree, name, bs, inlines, params = nil
  while tree
    call = recv = sep = mid = args = nil
    case tree.first
    when :def
      params = collect_params(tree[2])
      tree = tree[3]
      next
    when :defs
      params = collect_params(tree[4])
      tree = tree[5]
      next
    when :class
      name = 'class'
      tree = tree[3]
      next
    when :sclass, :module
      name = 'class'
      tree = tree[2]
      next
    when :method_add_arg
      _, mid, (_, (_, args)) = tree
      case mid.first
      when :call
        _, recv, sep, mid = mid
      when :fcall
        _, mid = mid
      else
        mid = nil
      end
    when :vcall
      _, mid = tree
    when :command               # FCALL
      _, mid, (_, args) = tree
    when :call, :command_call   # CALL
      _, recv, sep, mid, (_, args) = tree
    end
    if mid
      raise "unknown sexp: #{mid.inspect}" unless mid.first == :@ident
      _, mid, (lineno,) = mid
      if recv
        func_name = nil
        case recv.first
        when :var_ref
          _, recv = recv
          if recv.first == :@const and recv[1] == "Primitive"
            func_name = mid.to_s
          end
        when :vcall
          _, recv = recv
          if recv.first == :@ident and recv[1] == "__builtin"
            func_name = mid.to_s
          end
        end
        collect_builtin(base, recv, name, bs, inlines) unless func_name
      else
        func_name = mid[/\A__builtin_(.+)/, 1]
      end
      if func_name
        cfunc_name = func_name
        args.pop unless (args ||= []).last
        argc = args.size

        if /(.+)\!\z/ =~ func_name
          case $1
          when 'attr'
            text = inline_text(argc, args.first)
            if text != 'inline'
              raise "Only 'inline' is allowed to be annotated (but got: '#{text}')"
            end
            break
          when 'cstmt'
            text = inline_text argc, args.first

            func_name = "_bi#{inlines.size}"
            cfunc_name = make_cfunc_name(inlines, name, lineno)
            inlines[cfunc_name] = [lineno, text, params, func_name]
            argc -= 1
          when 'cexpr', 'cconst'
            text = inline_text argc, args.first
            code = "return #{text};"

            func_name = "_bi#{inlines.size}"
            cfunc_name = make_cfunc_name(inlines, name, lineno)

            params = [] if $1 == 'cconst'
            inlines[cfunc_name] = [lineno, code, params, func_name]
            argc -= 1
          when 'cinit'
            text = inline_text argc, args.first
            func_name = nil
            inlines[inlines.size] = [nil, [lineno, text, nil, nil]]
            argc -= 1
          end
        end

        if bs[func_name] &&
           bs[func_name] != [argc, cfunc_name]
          raise "same builtin function \"#{func_name}\", but different arity (was #{bs[func_name]} but #{argc})"
        end

        bs[func_name] = [argc, cfunc_name] if func_name
      end
      break unless tree = args
    end

    tree.each do |t|
      collect_builtin base, t, name, bs, inlines, params if Array === t
    end
    break
  end
end
# ruby mk_builtin_loader.rb TARGET_FILE.rb
# #=> generate TARGET_FILE.rbinc
#

def mk_builtin_header file
  base = File.basename(file, '.rb')
  ofile = "#{file}inc"

  # bs = { func_name => argc }
  collect_builtin(base, Ripper.sexp(File.read(file)), 'top', bs = {}, inlines = {})

  begin
    f = open(ofile, 'w')
  rescue Errno::EACCES
    # Fall back to the current directory
    f = open(File.basename(ofile), 'w')
  end
  begin
    f.puts "// -*- c -*-"
    f.puts "// DO NOT MODIFY THIS FILE DIRECTLY."
    f.puts "// auto-generated file"
    f.puts "//   by #{__FILE__}"
    f.puts "//   with #{file}"
    f.puts '#include "internal/compilers.h"     /* for MAYBE_UNUSED */'
    f.puts '#include "internal/warnings.h"      /* for COMPILER_WARNING_PUSH */'
    f.puts '#include "ruby/ruby.h"              /* for VALUE */'
    f.puts '#include "builtin.h"                /* for RB_BUILTIN_FUNCTION */'
    f.puts 'struct rb_execution_context_struct; /* in vm_core.h */'
    f.puts
    lineno = 11
    line_file = file.gsub('\\', '/')

    inlines.each{|cfunc_name, (body_lineno, text, params, func_name)|
      if String === cfunc_name
        f.puts "static VALUE #{cfunc_name}(struct rb_execution_context_struct *ec, const VALUE self) {"
        lineno += 1

        params.reverse_each.with_index{|param, i|
          next unless Symbol === param
          f.puts "MAYBE_UNUSED(const VALUE) #{param} = rb_vm_lvar(ec, #{-3 - i});"
          lineno += 1
        }
        f.puts "#line #{body_lineno} \"#{line_file}\""
        lineno += 1

        f.puts text
        lineno += text.count("\n") + 1

        f.puts "#line #{lineno + 2} \"#{ofile}\"" # TODO: restore line number.
        f.puts "}"
        lineno += 2
      else
        # cinit!
        f.puts "#line #{body_lineno} \"#{line_file}\""
        lineno += 1
        f.puts text
        lineno += text.count("\n") + 1
        f.puts "#line #{lineno + 2} \"#{ofile}\"" # TODO: restore line number.
        lineno += 1
      end
    }

    f.puts "void Init_builtin_#{base}(void)"
    f.puts "{"

    table = "#{base}_table"
    f.puts "  // table definition"
    f.puts "  static const struct rb_builtin_function #{table}[] = {"
    bs.each.with_index{|(func, (argc, cfunc_name)), i|
      f.puts "    RB_BUILTIN_FUNCTION(#{i}, #{func}, #{cfunc_name}, #{argc}),"
    }
    f.puts "    RB_BUILTIN_FUNCTION(-1, NULL, NULL, 0),"
    f.puts "  };"

    f.puts
    f.puts "  // arity_check"
    f.puts "COMPILER_WARNING_PUSH"
    f.puts "#if GCC_VERSION_SINCE(5, 1, 0) || __clang__"
    f.puts "COMPILER_WARNING_ERROR(-Wincompatible-pointer-types)"
    f.puts "#endif"
    bs.each{|func, (argc, cfunc_name)|
      f.puts "  if (0) rb_builtin_function_check_arity#{argc}(#{cfunc_name});"
    }
    f.puts "COMPILER_WARNING_POP"

    f.puts
    f.puts "  // load"
    f.puts "  rb_load_with_builtin_functions(#{base.dump}, #{table});"

    f.puts "}"
  ensure
    f.close
  end
end

ARGV.each{|file|
  # feature.rb => load_feature.inc
  mk_builtin_header file
}
