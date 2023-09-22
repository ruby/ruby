# frozen_string_literal: true

module YARP
  class CompileFilesTest < Test::Unit::TestCase
    def setup
      @previous_default_external = Encoding.default_external
      ignore_warnings { Encoding.default_external = Encoding::UTF_8 }
    end

    def teardown
      ignore_warnings { Encoding.default_external = @previous_default_external }
    end

    # Fixtures that currently lead to crashes when run
    # first ones are assertion falures
    crashes = %w(
      method_calls.txt
      unparser/corpus/literal/since/31.txt
      whitequark/anonymous_blockarg.txt

      break.txt
      seattlerb/mlhs_front_anonsplat.txt
      whitequark/masgn_const.txt
      seattlerb/masgn_anon_splat_arg.txt
      unparser/corpus/literal/assignment.txt
      whitequark/masgn_nested.txt
      seattlerb/masgn_colon3.txt
      seattlerb/masgn_command_call.txt
      whitequark/args_assocs.txt
      seattlerb/call_block_arg_named.txt
      seattlerb/mlhs_back_anonsplat.txt
      endless_range_in_conditional.txt
      seattlerb/masgn_var_star_var.txt
      if.txt
      keywords.txt
      next.txt
      variables.txt
      procs.txt
      seattlerb/assoc__bare.txt
      seattlerb/mlhs_mid_anonsplat.txt
      seattlerb/block_break.txt
      seattlerb/block_next.txt
      seattlerb/masgn_star.txt
      unless.txt
      unparser/corpus/literal/control.txt
      unparser/corpus/literal/since/32.txt
      whitequark/break.txt
      whitequark/break_block.txt
      whitequark/forwarded_argument_with_kwrestarg.txt
      whitequark/forwarded_argument_with_restarg.txt
      whitequark/forwarded_kwrestarg.txt
      whitequark/forwarded_kwrestarg_with_additional_kwarg.txt
      whitequark/forwarded_restarg.txt
      whitequark/hash_pair_value_omission.txt
      whitequark/kwoptarg_with_kwrestarg_and_forwarded_args.txt
      whitequark/masgn_splat.txt
      whitequark/next.txt
      whitequark/next_block.txt
      whitequark/redo.txt
      whitequark/bug_regex_verification.txt
    )

    failures = %w(
      arrays.txt
      classes.txt
      constants.txt
      methods.txt
      modules.txt
      not.txt
      seattlerb/bug191.txt
      seattlerb/difficult1_line_numbers2.txt
      seattlerb/difficult2_.txt
      seattlerb/difficult3_4.txt
      seattlerb/difficult7_.txt
      seattlerb/dsym_esc_to_sym.txt
      seattlerb/flip2_env_lvar.txt
      seattlerb/magic_encoding_comment.txt
      seattlerb/parse_if_not_canonical.txt
      seattlerb/parse_if_not_noncanonical.txt
      seattlerb/return_call_assocs.txt
      seattlerb/str_interp_ternary_or_label.txt
      ternary_operator.txt
      undef.txt
      unparser/corpus/literal/class.txt
      unparser/corpus/literal/flipflop.txt
      unparser/corpus/literal/module.txt
      unparser/corpus/literal/variables.txt
      unparser/corpus/semantic/and.txt
      unparser/corpus/semantic/dstr.txt
      whitequark/ambiuous_quoted_label_in_ternary_operator.txt
      whitequark/array_assocs.txt
      whitequark/array_splat.txt
      whitequark/cond_begin.txt
      whitequark/cond_eflipflop.txt
      whitequark/cond_iflipflop.txt
      whitequark/hash_label_end.txt
      whitequark/if.txt
      whitequark/if_else.txt
      whitequark/if_elsif.txt
      whitequark/if_mod.txt
      whitequark/if_nl_then.txt
      whitequark/if_while_after_class__since_32.txt
      whitequark/parser_bug_830.txt
      whitequark/send_attr_asgn.txt
      whitequark/ternary.txt
      whitequark/ternary_ambiguous_symbol.txt
      whitequark/unless.txt
      whitequark/unless_else.txt
      whitequark/unless_mod.txt
    )

    # The FOCUS environment variable allows you to specify one particular fixture
    # to test, instead of all of them.
    base = File.join(__dir__, "fixtures")
    relatives = ENV["FOCUS"] ? [ENV["FOCUS"]] : Dir["**/*.txt", base: base]

    relatives = relatives - crashes - failures

    relatives.each do |relative|
      filepath = File.join(base, relative)
      snapshot = File.expand_path(File.join("compiler/snapshots", relative), __dir__)

      directory = File.dirname(snapshot)
      FileUtils.mkdir_p(directory) unless File.directory?(directory)
      define_method "test_filepath_#{relative}" do
        # First, read the source from the filepath. Use binmode to avoid converting CRLF on Windows,
        # and explicitly set the external encoding to UTF-8 to override the binmode default.
        source = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)

        # We catch NotImplementedErrors since we have no expectations for
        # ability to compile nodes that haven't yet been implemented
        begin
          result = RubyVM::InstructionSequence.compile_yarp(source)
        rescue NotImplementedError
          return
        end

        # Next, pretty print the source.
        printed = result.disasm

        if File.exist?(snapshot)
          saved = File.read(snapshot)

          # If the snapshot file exists, but the printed value does not match the
          # snapshot, then update the snapshot file.
          if printed != saved
            File.write(snapshot, printed)
            warn("Updated snapshot at #{snapshot}.")
          end

          # If the snapshot file exists, then assert that the printed value
          # matches the snapshot.
          assert_equal(saved, printed)
        else
          # If the snapshot file does not yet exist, then write it out now.
          File.write(snapshot, printed)
          warn("Created snapshot at #{snapshot}.")
        end
      end
    end

    private

    def ignore_warnings
      previous_verbosity = $VERBOSE
      $VERBOSE = nil
      yield
    ensure
      $VERBOSE = previous_verbosity
    end
  end
end
