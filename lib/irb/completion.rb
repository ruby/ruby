# frozen_string_literal: false
#
#   irb/completion.rb -
#   	$Release Version: 0.9$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#       From Original Idea of shugo@ruby-lang.org
#

autoload :RDoc, "rdoc"

module IRB
  module InputCompletor # :nodoc:


    # Set of reserved words used by Ruby, you should not use these for
    # constants or variables
    ReservedWords = %w[
      __ENCODING__ __LINE__ __FILE__
      BEGIN END
      alias and
      begin break
      case class
      def defined? do
      else elsif end ensure
      false for
      if in
      module
      next nil not
      or
      redo rescue retry return
      self super
      then true
      undef unless until
      when while
      yield
    ]

    BASIC_WORD_BREAK_CHARACTERS = " \t\n`><=;|&{("

    CompletionProc = proc { |input|
      retrieve_completion_data(input).compact.map{ |i| i.encode(Encoding.default_external) }
    }

    def self.retrieve_completion_data(input, bind: IRB.conf[:MAIN_CONTEXT].workspace.binding, doc_namespace: false)
      case input
      when /^((["'`]).*\2)\.([^.]*)$/
        # String
        receiver = $1
        message = Regexp.quote($3)

        candidates = String.instance_methods.collect{|m| m.to_s}
        if doc_namespace
          "String.#{message}"
        else
          select_message(receiver, message, candidates)
        end

      when /^(\/[^\/]*\/)\.([^.]*)$/
        # Regexp
        receiver = $1
        message = Regexp.quote($2)

        candidates = Regexp.instance_methods.collect{|m| m.to_s}
        if doc_namespace
          "Regexp.#{message}"
        else
          select_message(receiver, message, candidates)
        end

      when /^([^\]]*\])\.([^.]*)$/
        # Array
        receiver = $1
        message = Regexp.quote($2)

        candidates = Array.instance_methods.collect{|m| m.to_s}
        if doc_namespace
          "Array.#{message}"
        else
          select_message(receiver, message, candidates)
        end

      when /^([^\}]*\})\.([^.]*)$/
        # Proc or Hash
        receiver = $1
        message = Regexp.quote($2)

        proc_candidates = Proc.instance_methods.collect{|m| m.to_s}
        hash_candidates = Hash.instance_methods.collect{|m| m.to_s}
        if doc_namespace
          ["Proc.#{message}", "Hash.#{message}"]
        else
          select_message(receiver, message, proc_candidates | hash_candidates)
        end

      when /^(:[^:.]*)$/
        # Symbol
        return nil if doc_namespace
        sym = $1
        candidates = Symbol.all_symbols.collect do |s|
          ":" + s.id2name.encode(Encoding.default_external)
        rescue Encoding::UndefinedConversionError
          # ignore
        end
        candidates.grep(/^#{Regexp.quote(sym)}/)

      when /^::([A-Z][^:\.\(]*)$/
        # Absolute Constant or class methods
        receiver = $1
        candidates = Object.constants.collect{|m| m.to_s}
        if doc_namespace
          candidates.find { |i| i == receiver }
        else
          candidates.grep(/^#{receiver}/).collect{|e| "::" + e}
        end

      when /^([A-Z].*)::([^:.]*)$/
        # Constant or class methods
        receiver = $1
        message = Regexp.quote($2)
        begin
          candidates = eval("#{receiver}.constants.collect{|m| m.to_s}", bind)
          candidates |= eval("#{receiver}.methods.collect{|m| m.to_s}", bind)
        rescue Exception
          candidates = []
        end
        if doc_namespace
          "#{receiver}::#{message}"
        else
          select_message(receiver, message, candidates, "::")
        end

      when /^(:[^:.]+)(\.|::)([^.]*)$/
        # Symbol
        receiver = $1
        sep = $2
        message = Regexp.quote($3)

        candidates = Symbol.instance_methods.collect{|m| m.to_s}
        if doc_namespace
          "Symbol.#{message}"
        else
          select_message(receiver, message, candidates, sep)
        end

      when /^(?<num>-?(?:0[dbo])?[0-9_]+(?:\.[0-9_]+)?(?:(?:[eE][+-]?[0-9]+)?i?|r)?)(?<sep>\.|::)(?<mes>[^.]*)$/
        # Numeric
        receiver = $~[:num]
        sep = $~[:sep]
        message = Regexp.quote($~[:mes])

        begin
          instance = eval(receiver, bind)
          if doc_namespace
            "#{instance.class.name}.#{message}"
          else
            candidates = instance.methods.collect{|m| m.to_s}
            select_message(receiver, message, candidates, sep)
          end
        rescue Exception
          if doc_namespace
            nil
          else
            candidates = []
          end
        end

      when /^(-?0x[0-9a-fA-F_]+)(\.|::)([^.]*)$/
        # Numeric(0xFFFF)
        receiver = $1
        sep = $2
        message = Regexp.quote($3)

        begin
          instance = eval(receiver, bind)
          if doc_namespace
            "#{instance.class.name}.#{message}"
          else
            candidates = instance.methods.collect{|m| m.to_s}
            select_message(receiver, message, candidates, sep)
          end
        rescue Exception
          if doc_namespace
            nil
          else
            candidates = []
          end
        end

      when /^(\$[^.]*)$/
        # global var
        gvar = $1
        all_gvars = global_variables.collect{|m| m.to_s}
        if doc_namespace
          all_gvars.find{ |i| i == gvar }
        else
          all_gvars.grep(Regexp.new(Regexp.quote(gvar)))
        end

      when /^([^."].*)(\.|::)([^.]*)$/
        # variable.func or func.func
        receiver = $1
        sep = $2
        message = Regexp.quote($3)

        gv = eval("global_variables", bind).collect{|m| m.to_s}.push("true", "false", "nil")
        lv = eval("local_variables", bind).collect{|m| m.to_s}
        iv = eval("instance_variables", bind).collect{|m| m.to_s}
        cv = eval("self.class.constants", bind).collect{|m| m.to_s}

        if (gv | lv | iv | cv).include?(receiver) or /^[A-Z]/ =~ receiver && /\./ !~ receiver
          # foo.func and foo is var. OR
          # foo::func and foo is var. OR
          # foo::Const and foo is var. OR
          # Foo::Bar.func
          begin
            candidates = []
            rec = eval(receiver, bind)
            if sep == "::" and rec.kind_of?(Module)
              candidates = rec.constants.collect{|m| m.to_s}
            end
            candidates |= rec.methods.collect{|m| m.to_s}
          rescue Exception
            candidates = []
          end
        else
          # func1.func2
          candidates = []
          to_ignore = ignored_modules
          ObjectSpace.each_object(Module){|m|
            next if (to_ignore.include?(m) rescue true)
            candidates.concat m.instance_methods(false).collect{|x| x.to_s}
          }
          candidates.sort!
          candidates.uniq!
        end
        if doc_namespace
          "#{rec.class.name}#{sep}#{candidates.find{ |i| i == message }}"
        else
          select_message(receiver, message, candidates, sep)
        end

      when /^\.([^.]*)$/
        # unknown(maybe String)

        receiver = ""
        message = Regexp.quote($1)

        candidates = String.instance_methods(true).collect{|m| m.to_s}
        if doc_namespace
          "String.#{candidates.find{ |i| i == message }}"
        else
          select_message(receiver, message, candidates)
        end

      else
        candidates = eval("methods | private_methods | local_variables | instance_variables | self.class.constants", bind).collect{|m| m.to_s}
        candidates |= ReservedWords

        if doc_namespace
          candidates.find{ |i| i == input }
        else
          candidates.grep(/^#{Regexp.quote(input)}/)
        end
      end
    end

    PerfectMatchedProc = ->(matched, bind: IRB.conf[:MAIN_CONTEXT].workspace.binding) {
      RDocRIDriver ||= RDoc::RI::Driver.new
      if matched =~ /\A(?:::)?RubyVM/ and not ENV['RUBY_YES_I_AM_NOT_A_NORMAL_USER']
        IRB.send(:easter_egg)
        return
      end
      namespace = retrieve_completion_data(matched, bind: bind, doc_namespace: true)
      return unless namespace
      if namespace.is_a?(Array)
        out = RDoc::Markup::Document.new
        namespace.each do |m|
          begin
            RDocRIDriver.add_method(out, m)
          rescue RDoc::RI::Driver::NotFoundError
          end
        end
        RDocRIDriver.display(out)
      else
        begin
          RDocRIDriver.display_names([namespace])
        rescue RDoc::RI::Driver::NotFoundError
        end
      end
    }

    # Set of available operators in Ruby
    Operators = %w[% & * ** + - / < << <= <=> == === =~ > >= >> [] []= ^ ! != !~]

    def self.select_message(receiver, message, candidates, sep = ".")
      candidates.grep(/^#{message}/).collect do |e|
        case e
        when /^[a-zA-Z_]/
          receiver + sep + e
        when /^[0-9]/
        when *Operators
          #receiver + " " + e
        end
      end
    end

    def self.ignored_modules
      # We could cache the result, but this is very fast already.
      # By using this approach, we avoid Module#name calls, which are
      # relatively slow when there are a lot of anonymous modules defined.
      s = {}

      scanner = lambda do |m|
        next if s.include?(m) # IRB::ExtendCommandBundle::EXCB recurses.
        s[m] = true
        m.constants(false).each do |c|
          value = m.const_get(c)
          scanner.call(value) if value.is_a?(Module)
        end
      end

      %i(IRB RubyLex).each do |sym|
        next unless Object.const_defined?(sym)
        scanner.call(Object.const_get(sym))
      end

      s.delete(IRB::Context) if defined?(IRB::Context)

      s
    end
  end
end
