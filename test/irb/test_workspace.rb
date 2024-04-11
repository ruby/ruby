# frozen_string_literal: false
require 'tempfile'
require 'irb'
require 'irb/workspace'
require 'irb/color'

require_relative "helper"

module TestIRB
  class WorkSpaceTest < TestCase
    def test_code_around_binding
      IRB.conf[:USE_COLORIZE] = false
      Tempfile.create('irb') do |f|
        code = <<~RUBY
          # 1
          # 2
          IRB::WorkSpace.new(binding) # 3
          # 4
          # 5
        RUBY
        f.print(code)
        f.close

        workspace = eval(code, binding, f.path)
        assert_equal(<<~EOS, without_term { workspace.code_around_binding })

          From: #{f.path} @ line 3 :

              1: # 1
              2: # 2
           => 3: IRB::WorkSpace.new(binding) # 3
              4: # 4
              5: # 5

        EOS
      end
    ensure
      IRB.conf.delete(:USE_COLORIZE)
    end

    def test_code_around_binding_with_existing_unreadable_file
      pend 'chmod cannot make file unreadable on windows' if windows?
      pend 'skipped in root privilege' if Process.uid == 0

      Tempfile.create('irb') do |f|
        code = "IRB::WorkSpace.new(binding)\n"
        f.print(code)
        f.close

        File.chmod(0, f.path)

        workspace = eval(code, binding, f.path)
        assert_equal(nil, workspace.code_around_binding)
      end
    end

    def test_code_around_binding_with_script_lines__
      IRB.conf[:USE_COLORIZE] = false
      with_script_lines do |script_lines|
        Tempfile.create('irb') do |f|
          code = "IRB::WorkSpace.new(binding)\n"
          script_lines[f.path] = code.split(/^/)

          workspace = eval(code, binding, f.path)
          assert_equal(<<~EOS, without_term { workspace.code_around_binding })

            From: #{f.path} @ line 1 :

             => 1: IRB::WorkSpace.new(binding)

          EOS
        end
      end
    ensure
      IRB.conf.delete(:USE_COLORIZE)
    end

    def test_code_around_binding_on_irb
      workspace = eval("IRB::WorkSpace.new(binding)", binding, "(irb)")
      assert_equal(nil, workspace.code_around_binding)
    end


    def test_toplevel_binding_local_variables
      bug17623 = '[ruby-core:102468]'
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      top_srcdir = "#{__dir__}/../.."
      irb_path = nil
      %w[exe libexec].find do |dir|
        irb_path = "#{top_srcdir}/#{dir}/irb"
        File.exist?(irb_path)
      end or omit 'irb command not found'
      assert_in_out_err(bundle_exec + ['-W0', "-C#{top_srcdir}", '-e', <<~RUBY, '--', '-f', '--'], 'binding.local_variables', /\[:_\]/, [], bug17623)
        version = 'xyz' # typical rubygems loading file
        load('#{irb_path}')
      RUBY
    end

    private

    def with_script_lines
      script_lines = nil
      debug_lines = {}
      Object.class_eval do
        if defined?(SCRIPT_LINES__)
          script_lines = SCRIPT_LINES__
          remove_const :SCRIPT_LINES__
        end
        const_set(:SCRIPT_LINES__, debug_lines)
      end
      yield debug_lines
    ensure
      Object.class_eval do
        remove_const :SCRIPT_LINES__
        const_set(:SCRIPT_LINES__, script_lines) if script_lines
      end
    end

    def without_term
      env = ENV.to_h.dup
      ENV.delete('TERM')
      yield
    ensure
      ENV.replace(env)
    end
  end
end
