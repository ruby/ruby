
def collect_builtin base, iseq_ary, bs, inlines
  code = iseq_ary[13]
  params = iseq_ary[10]
  prev_insn = nil
  lineno = nil

  code.each{|insn|
    case insn
    when Array
      # ok
    when Integer
      lineno = insn
      next
    else
      next
    end

    next unless Array === insn
    case insn[0]
    when :send
      ci = insn[1]
      if /\A__builtin_(.+)/ =~ ci[:mid]
        func_name = $1
        argc = ci[:orig_argc]

        if func_name ==  'inline!'
          raise "argc (#{argc}) of inline! should be 1" unless argc == 1
          raise "1st argument should be string literal" unless prev_insn[0] == :putstring
          text = prev_insn[1].rstrip

          func_name = "rb_compiled_inline#{inlines.size}"
          inlines << [func_name, [lineno, text, params]]
          argc -= 1
        end

        if bs[func_name] &&
           bs[func_name] != argc
          raise "same builtin function \"#{func_name}\", but different arity (was #{bs[func_name]} but #{argc})"
        end

        bs[func_name] = argc
      end
    else
      insn[1..-1].each{|op|
        if op.is_a?(Array) && op[0] == "YARVInstructionSequence/SimpleDataFormat"
          collect_builtin base, op, bs, inlines
        end
      }
    end
    prev_insn = insn
  }
end
# ruby mk_builtin_loader.rb TARGET_FILE.rb
# #=> generate TARGET_FILE.rbinc
#

def mk_builtin_header file
  base = File.basename(file, '.rb')
  ofile = "#{base}.rbinc"

  # bs = { func_name => argc }
  collect_builtin(base, RubyVM::InstructionSequence.compile_file(file, false).to_a, bs = {}, inlines = [])

  open(ofile, 'w'){|f|
    f.puts "// -*- c -*-"
    f.puts "// DO NOT MODIFY THIS FILE DIRECTLY."
    f.puts "// auto-generated file"
    f.puts "//   by #{__FILE__}"
    f.puts "//   with #{file}"
    f.puts
    lineno = 6

    inlines.each{|name, (body_lineno, text, params)|
      f.puts "static VALUE #{name}(rb_execution_context_t *ec, const VALUE self) {"
      lineno += 1

      params.reverse_each.with_index{|param, i|
        next unless Symbol === param
        f.puts "MAYBE_UNUSED(const VALUE) #{param} = rb_vm_lvar(ec, #{-3 - i});"
        lineno += 1
      }
      f.puts "#line #{body_lineno} \"#{file}\""
      lineno += 1

      f.puts text
      lineno += text.count("\n") + 1

      f.puts "#line #{lineno + 2} \"#{ofile}\"" # TODO: restore line number.
      f.puts "}"
      lineno += 2
    }

    f.puts "static void load_#{base}(void)"
    f.puts "{"

    table = "#{base}_table"
    f.puts "  // table definition"
    f.puts "  static const struct rb_builtin_function #{table}[] = {"
    bs.each.with_index{|(func, argc), i|
      f.puts "    RB_BUILTIN_FUNCTION(#{i}, #{func}, #{argc}),"
    }
    f.puts "    RB_BUILTIN_FUNCTION(-1, NULL, 0),"
    f.puts "  };"

    f.puts
    f.puts "  // arity_check"
    f.puts "COMPILER_WARNING_PUSH"
    f.puts "#if GCC_VERSION_SINCE(5, 1, 0) || __clang__"
    f.puts "COMPILER_WARNING_ERROR(-Wincompatible-pointer-types)"
    f.puts "#endif"
    bs.each{|func, argc|
      f.puts "  if (0) rb_builtin_function_check_arity#{argc}(#{func});"
    }
    f.puts "COMPILER_WARNING_POP"


    f.puts
    f.puts "  // load"
    f.puts "  rb_load_with_builtin_functions(#{base.dump}, #{table});"

    f.puts "}"
  }
end

ARGV.each{|file|
  # feature.rb => load_feature.inc
  mk_builtin_header file
}
