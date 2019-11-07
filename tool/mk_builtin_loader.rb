
def collect_builtin iseq_ary, bs
  code = iseq_ary[13]

  code.each{|insn|
    next unless Array === insn
    case insn[0]
    when :send
      ci = insn[1]
      if /\A__builtin_(.+)/ =~ ci[:mid]
        func_name = $1
        argc = ci[:orig_argc]

        if bs[func_name] && bs[func_name] != argc
          raise
        end
        bs[func_name] = argc
      end
    else
      insn[1..-1].each{|op|
        if op[0] == "YARVInstructionSequence/SimpleDataFormat"
          collect_builtin op, bs
        end
      }
    end
  }
end
# ruby mk_builtin_loader.rb TARGET_FILE.rb
# #=> generate load_TARGET_FILE.inc
#

def mk_builtin_header file
  base = File.basename(file, '.rb')
  ofile = File.join("load_#{base}.inc")

  collect_builtin(RubyVM::InstructionSequence.compile_file(file, false).to_a, bs = {})

  open(ofile, 'w'){|f|
    f.puts "// DO NOT MODIFY THIS FILE DIRECTLY."
    f.puts "// auto-generated file"
    f.puts "//   by #{__FILE__}"
    f.puts "//   with #{file}"
    f.puts

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
    bs.each{|func, argc|
      f.puts "  if (0) rb_builtin_function_check_arity#{argc}(#{func});"
    }

    path = File.expand_path(file)
    f.puts
    f.puts "  // load"
    f.puts "  rb_load_with_builtin_functions(\"#{base}\", \"#{file}\", #{table});"

    f.puts "}"
  }
end

ARGV.each{|file|
  # feature.rb => load_feature.inc
  path = File.expand_path(file)
  mk_builtin_header path
}
