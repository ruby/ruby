# frozen_string_literal: false
#
#   irb/workspace-binding.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#
module IRB # :nodoc:
  class WorkSpace
    # Creates a new workspace.
    #
    # set self to main if specified, otherwise
    # inherit main from TOPLEVEL_BINDING.
    def initialize(*main)
      if main[0].kind_of?(Binding)
        @binding = main.shift
      elsif IRB.conf[:SINGLE_IRB]
        @binding = TOPLEVEL_BINDING
      else
        case IRB.conf[:CONTEXT_MODE]
        when 0	# binding in proc on TOPLEVEL_BINDING
          @binding = eval("proc{binding}.call",
                          TOPLEVEL_BINDING,
                          __FILE__,
                          __LINE__)
        when 1	# binding in loaded file
          require "tempfile"
          f = Tempfile.open("irb-binding")
          f.print <<EOF
      $binding = binding
EOF
          f.close
          load f.path
          @binding = $binding

        when 2	# binding in loaded file(thread use)
          unless defined? BINDING_QUEUE
            IRB.const_set(:BINDING_QUEUE, Thread::SizedQueue.new(1))
            Thread.abort_on_exception = true
            Thread.start do
              eval "require \"irb/ws-for-case-2\"", TOPLEVEL_BINDING, __FILE__, __LINE__
            end
            Thread.pass
          end
          @binding = BINDING_QUEUE.pop

        when 3	# binding in function on TOPLEVEL_BINDING(default)
          @binding = eval("self.class.send(:remove_method, :irb_binding) if defined?(irb_binding); def irb_binding; private; binding; end; irb_binding",
                          TOPLEVEL_BINDING,
                          __FILE__,
                          __LINE__ - 3)
        end
      end
      if main.empty?
        @main = eval("self", @binding)
      else
        @main = main[0]
        IRB.conf[:__MAIN__] = @main
        case @main
        when Module
          @binding = eval("IRB.conf[:__MAIN__].module_eval('binding', __FILE__, __LINE__)", @binding, __FILE__, __LINE__)
        else
          begin
            @binding = eval("IRB.conf[:__MAIN__].instance_eval('binding', __FILE__, __LINE__)", @binding, __FILE__, __LINE__)
          rescue TypeError
            IRB.fail CantChangeBinding, @main.inspect
          end
        end
      end
      @binding.local_variable_set(:_, nil)
    end

    # The Binding of this workspace
    attr_reader :binding
    # The top-level workspace of this context, also available as
    # <code>IRB.conf[:__MAIN__]</code>
    attr_reader :main

    # Evaluate the given +statements+ within the  context of this workspace.
    def evaluate(context, statements, file = __FILE__, line = __LINE__)
      eval(statements, @binding, file, line)
    end

    def local_variable_set(name, value)
      @binding.local_variable_set(name, value)
    end

    def local_variable_get(name)
      @binding.local_variable_get(name)
    end

    # error message manipulator
    def filter_backtrace(bt)
      case IRB.conf[:CONTEXT_MODE]
      when 0
        return nil if bt =~ /\(irb_local_binding\)/
      when 1
        if(bt =~ %r!/tmp/irb-binding! or
            bt =~ %r!irb/.*\.rb! or
            bt =~ /irb\.rb/)
          return nil
        end
      when 2
        return nil if bt =~ /irb\/.*\.rb/
        return nil if bt =~ /irb\.rb/
      when 3
        return nil if bt =~ /irb\/.*\.rb/
        return nil if bt =~ /irb\.rb/
        bt = bt.sub(/:\s*in `irb_binding'/, '')
      end
      bt
    end

    def code_around_binding
      if @binding.respond_to?(:source_location)
        file, pos = @binding.source_location
      else
        file, pos = @binding.eval('[__FILE__, __LINE__]')
      end

      if defined?(::SCRIPT_LINES__[file]) && lines = ::SCRIPT_LINES__[file]
        code = ::SCRIPT_LINES__[file].join('')
      else
        begin
          code = File.read(file)
        rescue SystemCallError
          return
        end
      end

      # NOT using #use_colorize? of IRB.conf[:MAIN_CONTEXT] because this method may be called before IRB::Irb#run
      use_colorize = IRB.conf.fetch(:USE_COLORIZE, true)
      if use_colorize
        lines = Color.colorize_code(code).lines
      else
        lines = code.lines
      end
      pos -= 1

      start_pos = [pos - 5, 0].max
      end_pos   = [pos + 5, lines.size - 1].min

      if use_colorize
        fmt = " %2s #{Color.colorize("%#{end_pos.to_s.length}d", [:BLUE, :BOLD])}: %s"
      else
        fmt = " %2s %#{end_pos.to_s.length}d: %s"
      end
      body = (start_pos..end_pos).map do |current_pos|
        sprintf(fmt, pos == current_pos ? '=>' : '', current_pos + 1, lines[current_pos])
      end.join("")
      "\nFrom: #{file} @ line #{pos + 1} :\n\n#{body}#{Color.clear}\n"
    end

    def IRB.delete_caller
    end
  end
end
