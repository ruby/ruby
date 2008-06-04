#= parse_f95.rb - Fortran95 Parser
#
#== Overview
#
#"parse_f95.rb" parses Fortran95 files with suffixes "f90", "F90", "f95"
#and "F95". Fortran95 files are expected to be conformed to Fortran95
#standards.
#
#== Rules
#
#Fundamental rules are same as that of the Ruby parser.
#But comment markers are '!' not '#'.
#
#=== Correspondence between RDoc documentation and Fortran95 programs
#
#"parse_f95.rb" parses main programs, modules, subroutines, functions,
#derived-types, public variables, public constants,
#defined operators and defined assignments.
#These components are described in items of RDoc documentation, as follows.
#
#Files :: Files (same as Ruby)
#Classes :: Modules
#Methods :: Subroutines, functions, variables, constants, derived-types, defined operators, defined assignments
#Required files :: Files in which imported modules, external subroutines and external functions are defined.
#Included Modules :: List of imported modules
#Attributes :: List of derived-types, List of imported modules all of whose components are published again
#
#Components listed in 'Methods' (subroutines, functions, ...)
#defined in modules are described in the item of 'Classes'.
#On the other hand, components defined in main programs or
#as external procedures are described in the item of 'Files'.
#
#=== Components parsed by default
#
#By default, documentation on public components (subroutines, functions, 
#variables, constants, derived-types, defined operators, 
#defined assignments) are generated. 
#With "--all" option, documentation on all components
#are generated (almost same as the Ruby parser).
#
#=== Information parsed automatically
#
#The following information is automatically parsed.
#
#* Types of arguments
#* Types of variables and constants
#* Types of variables in the derived types, and initial values
#* NAMELISTs and types of variables in them, and initial values
#
#Aliases by interface statement are described in the item of 'Methods'.
#
#Components which are imported from other modules and published again 
#are described in the item of 'Methods'.
#
#=== Format of comment blocks
#
#Comment blocks should be written as follows.
#Comment blocks are considered to be ended when the line without '!'
#appears.
#The indentation is not necessary.
#
#     ! (Top of file)
#     !
#     ! Comment blocks for the files.
#     !
#     !--
#     ! The comment described in the part enclosed by
#     ! "!--" and "!++" is ignored.
#     !++
#     !
#     module hogehoge
#       !
#       ! Comment blocks for the modules (or the programs).
#       !
#
#       private
#
#       logical            :: a     ! a private variable
#       real, public       :: b     ! a public variable
#       integer, parameter :: c = 0 ! a public constant
#
#       public :: c
#       public :: MULTI_ARRAY
#       public :: hoge, foo
#
#       type MULTI_ARRAY
#         !
#         ! Comment blocks for the derived-types.
#         !
#         real, pointer :: var(:) =>null() ! Comments block for the variables.
#         integer       :: num = 0
#       end type MULTI_ARRAY
#
#     contains
#
#       subroutine hoge( in,   &   ! Comment blocks between continuation lines are ignored.
#           &            out )
#         !
#         ! Comment blocks for the subroutines or functions
#         !
#         character(*),intent(in):: in ! Comment blocks for the arguments.
#         character(*),intent(out),allocatable,target  :: in
#                                      ! Comment blocks can be
#                                      ! written under Fortran statements.
#
#         character(32) :: file ! This comment parsed as a variable in below NAMELIST.
#         integer       :: id
#
#         namelist /varinfo_nml/ file, id
#                 !
#                 ! Comment blocks for the NAMELISTs.
#                 ! Information about variables are described above.
#                 !
#
#       ....
#
#       end subroutine hoge
#
#       integer function foo( in )
#         !
#         ! This part is considered as comment block.
#
#         ! Comment blocks under blank lines are ignored.
#         !
#         integer, intent(in):: inA ! This part is considered as comment block.
#
#                                   ! This part is ignored.
#
#       end function foo
#
#       subroutine hide( in,   &
#         &              out )      !:nodoc:
#         !
#         ! If "!:nodoc:" is described at end-of-line in subroutine
#         ! statement as above, the subroutine is ignored.
#         ! This assignment can be used to modules, subroutines,
#         ! functions, variables, constants, derived-types,
#         ! defined operators, defined assignments,
#         ! list of imported modules ("use" statement).
#         !
#
#       ....
#
#       end subroutine hide
#
#     end module hogehoge
#


require "rdoc/code_objects"

module RDoc

  class Token

    NO_TEXT = "??".freeze

    def initialize(line_no, char_no)
      @line_no = line_no
      @char_no = char_no
      @text    = NO_TEXT
    end
    # Because we're used in contexts that expect to return a token,
    # we set the text string and then return ourselves
    def set_text(text)
      @text = text
      self
    end

    attr_reader :line_no, :char_no, :text

  end

  # See rdoc/parsers/parse_f95.rb

  class Fortran95parser

    extend ParserFactory
    parse_files_matching(/\.((f|F)9(0|5)|F)$/)

    @@external_aliases = []
    @@public_methods   = []

    # "false":: Comments are below source code
    # "true" :: Comments are upper source code
    COMMENTS_ARE_UPPER  = false

    # Internal alias message
    INTERNAL_ALIAS_MES = "Alias for"

    # External alias message
    EXTERNAL_ALIAS_MES = "The entity is"

    # prepare to parse a Fortran 95 file
    def initialize(top_level, file_name, body, options, stats)
      @body = body
      @stats = stats
      @file_name  = file_name
      @options = options
      @top_level = top_level
      @progress = $stderr unless options.quiet
    end

    # define code constructs
    def scan

      # remove private comment
      remaining_code = remove_private_comments(@body)

      # continuation lines are united to one line
      remaining_code = united_to_one_line(remaining_code)

      # semicolons are replaced to line feed
      remaining_code = semicolon_to_linefeed(remaining_code)

      # collect comment for file entity
      whole_comment, remaining_code = collect_first_comment(remaining_code)
      @top_level.comment = whole_comment

      # String "remaining_code" is converted to Array "remaining_lines"
      remaining_lines = remaining_code.split("\n")

      # "module" or "program" parts are parsed (new)
      #
      level_depth = 0
      block_searching_flag = nil
      block_searching_lines = []
      pre_comment = []
      module_program_trailing = ""
      module_program_name = ""
      other_block_level_depth = 0
      other_block_searching_flag = nil
      remaining_lines.collect!{|line|
        if !block_searching_flag && !other_block_searching_flag
          if line =~ /^\s*?module\s+(\w+)\s*?(!.*?)?$/i
            block_searching_flag = :module
            block_searching_lines << line
            module_program_name = $1
            module_program_trailing = find_comments($2)
            next false
          elsif line =~ /^\s*?program\s+(\w+)\s*?(!.*?)?$/i ||
                 line =~ /^\s*?\w/ && !block_start?(line)
            block_searching_flag = :program
            block_searching_lines << line
            module_program_name = $1 || ""
            module_program_trailing = find_comments($2)
            next false

          elsif block_start?(line)
            other_block_searching_flag = true
            next line

          elsif line =~ /^\s*?!\s?(.*)/
            pre_comment << line
            next line
          else
            pre_comment = []
            next line
          end
        elsif other_block_searching_flag
          other_block_level_depth += 1 if block_start?(line)
          other_block_level_depth -= 1 if block_end?(line)
          if other_block_level_depth < 0
            other_block_level_depth = 0
            other_block_searching_flag = nil
          end
          next line
        end

        block_searching_lines << line
        level_depth += 1 if block_start?(line)
        level_depth -= 1 if block_end?(line)
        if level_depth >= 0
          next false
        end

        # "module_program_code" is formatted.
        # ":nodoc:" flag is checked.
        #
        module_program_code = block_searching_lines.join("\n")
        module_program_code = remove_empty_head_lines(module_program_code)
        if module_program_trailing =~ /^:nodoc:/
          # next loop to search next block
          level_depth = 0
          block_searching_flag = false
          block_searching_lines = []
          pre_comment = []
          next false
        end

        # NormalClass is created, and added to @top_level
        #
        if block_searching_flag == :module
          module_name = module_program_name
          module_code = module_program_code
          module_trailing = module_program_trailing
          progress "m"
          @stats.num_modules += 1
          f9x_module = @top_level.add_module NormalClass, module_name
          f9x_module.record_location @top_level

          f9x_comment = COMMENTS_ARE_UPPER ? 
            find_comments(pre_comment.join("\n"))  + "\n" + module_trailing :
              module_trailing + "\n" + find_comments(module_code.sub(/^.*$\n/i, ''))
          f9x_module.comment = f9x_comment
          parse_program_or_module(f9x_module, module_code)

          TopLevel.all_files.each do |name, toplevel|
            if toplevel.include_includes?(module_name, @options.ignore_case)
              if !toplevel.include_requires?(@file_name, @options.ignore_case)
                toplevel.add_require(Require.new(@file_name, ""))
              end
            end
            toplevel.each_classmodule{|m|
              if m.include_includes?(module_name, @options.ignore_case)
                if !m.include_requires?(@file_name, @options.ignore_case)
                  m.add_require(Require.new(@file_name, ""))
                end
              end
            }
          end
        elsif block_searching_flag == :program
          program_name = module_program_name
          program_code = module_program_code
          program_trailing = module_program_trailing
          progress "p"
          program_comment = COMMENTS_ARE_UPPER ? 
            find_comments(pre_comment.join("\n")) + "\n" + program_trailing : 
              program_trailing + "\n" + find_comments(program_code.sub(/^.*$\n/i, ''))
          program_comment = "\n\n= <i>Program</i> <tt>#{program_name}</tt>\n\n" \
                            + program_comment
          @top_level.comment << program_comment
          parse_program_or_module(@top_level, program_code, :private)
        end

        # next loop to search next block
        level_depth = 0
        block_searching_flag = false
        block_searching_lines = []
        pre_comment = []
        next false
      }

      remaining_lines.delete_if{ |line|
        line == false
      }

      # External subprograms and functions are parsed
      #
      parse_program_or_module(@top_level, remaining_lines.join("\n"),
                              :public, true)

      @top_level
    end  # End of scan

    private

    def parse_program_or_module(container, code,
                                visibility=:public, external=nil)
      return unless container
      return unless code
      remaining_lines = code.split("\n")
      remaining_code = "#{code}"

      #
      # Parse variables before "contains" in module
      #
      level_depth = 0
      before_contains_lines = []
      before_contains_code = nil
      before_contains_flag = nil
      remaining_lines.each{ |line|
        if !before_contains_flag
          if line =~ /^\s*?module\s+\w+\s*?(!.*?)?$/i
            before_contains_flag = true
          end
        else
          break if line =~ /^\s*?contains\s*?(!.*?)?$/i
          level_depth += 1 if block_start?(line)
          level_depth -= 1 if block_end?(line)
          break if level_depth < 0
          before_contains_lines << line
        end
      }
      before_contains_code = before_contains_lines.join("\n")
      if before_contains_code
        before_contains_code.gsub!(/^\s*?interface\s+.*?\s+end\s+interface.*?$/im, "")
        before_contains_code.gsub!(/^\s*?type[\s\,]+.*?\s+end\s+type.*?$/im, "")
      end

      #
      # Parse global "use"
      #
      use_check_code = "#{before_contains_code}"
      cascaded_modules_list = []
      while use_check_code =~ /^\s*?use\s+(\w+)(.*?)(!.*?)?$/i
        use_check_code = $~.pre_match
        use_check_code << $~.post_match
        used_mod_name = $1.strip.chomp
        used_list = $2 || ""
        used_trailing = $3 || ""
        next if used_trailing =~ /!:nodoc:/
        if !container.include_includes?(used_mod_name, @options.ignore_case)
          progress "."
          container.add_include Include.new(used_mod_name, "")
        end
        if ! (used_list =~ /\,\s*?only\s*?:/i )
          cascaded_modules_list << "\#" + used_mod_name
        end
      end

      #
      # Parse public and private, and store information.
      # This information is used when "add_method" and
      # "set_visibility_for" are called.
      #
      visibility_default, visibility_info = 
                parse_visibility(remaining_lines.join("\n"), visibility, container)
      @@public_methods.concat visibility_info
      if visibility_default == :public
        if !cascaded_modules_list.empty?
          cascaded_modules = 
            Attr.new("Cascaded Modules",
                     "Imported modules all of whose components are published again",
                     "",
                     cascaded_modules_list.join(", "))
          container.add_attribute(cascaded_modules)
        end
      end

      #
      # Check rename elements
      #
      use_check_code = "#{before_contains_code}"
      while use_check_code =~ /^\s*?use\s+(\w+)\s*?\,(.+)$/i
        use_check_code = $~.pre_match
        use_check_code << $~.post_match
        used_mod_name = $1.strip.chomp
        used_elements = $2.sub(/\s*?only\s*?:\s*?/i, '')
        used_elements.split(",").each{ |used|
          if /\s*?(\w+)\s*?=>\s*?(\w+)\s*?/ =~ used
            local = $1
            org = $2
            @@public_methods.collect!{ |pub_meth|
              if local == pub_meth["name"] ||
                  local.upcase == pub_meth["name"].upcase &&
                  @options.ignore_case
                pub_meth["name"] = org
                pub_meth["local_name"] = local
              end
              pub_meth
            }
          end
        }
      end

      #
      # Parse private "use"
      #
      use_check_code = remaining_lines.join("\n")
      while use_check_code =~ /^\s*?use\s+(\w+)(.*?)(!.*?)?$/i
        use_check_code = $~.pre_match
        use_check_code << $~.post_match
        used_mod_name = $1.strip.chomp
        used_trailing = $3 || ""
        next if used_trailing =~ /!:nodoc:/
        if !container.include_includes?(used_mod_name, @options.ignore_case)
          progress "."
          container.add_include Include.new(used_mod_name, "")
        end
      end

      container.each_includes{ |inc|
        TopLevel.all_files.each do |name, toplevel|
          indicated_mod = toplevel.find_symbol(inc.name,
                                               nil, @options.ignore_case)
          if indicated_mod
            indicated_name = indicated_mod.parent.file_relative_name
            if !container.include_requires?(indicated_name, @options.ignore_case)
              container.add_require(Require.new(indicated_name, ""))
            end
            break
          end
        end
      }

      #
      # Parse derived-types definitions
      #
      derived_types_comment = ""
      remaining_code = remaining_lines.join("\n")
      while remaining_code =~ /^\s*?
                                    type[\s\,]+(public|private)?\s*?(::)?\s*?
                                    (\w+)\s*?(!.*?)?$
                                    (.*?)
                                    ^\s*?end\s+type.*?$
                              /imx
        remaining_code = $~.pre_match
        remaining_code << $~.post_match
        typename = $3.chomp.strip
        type_elements = $5 || ""
        type_code = remove_empty_head_lines($&)
        type_trailing = find_comments($4)
        next if type_trailing =~ /^:nodoc:/
        type_visibility = $1
        type_comment = COMMENTS_ARE_UPPER ? 
          find_comments($~.pre_match) + "\n" + type_trailing :
            type_trailing + "\n" + find_comments(type_code.sub(/^.*$\n/i, ''))
        type_element_visibility_public = true
        type_code.split("\n").each{ |line|
          if /^\s*?private\s*?$/ =~ line
            type_element_visibility_public = nil
            break
          end
        } if type_code

        args_comment = ""
        type_args_info = nil

        if @options.show_all
          args_comment = find_arguments(nil, type_code, true)
        else
          type_public_args_list = []
          type_args_info = definition_info(type_code)
          type_args_info.each{ |arg|
            arg_is_public = type_element_visibility_public
            arg_is_public = true if arg.include_attr?("public")
            arg_is_public = nil if arg.include_attr?("private")
            type_public_args_list << arg.varname if arg_is_public
          }
          args_comment = find_arguments(type_public_args_list, type_code)
        end

        type = AnyMethod.new("type #{typename}", typename)
        type.singleton = false
        type.params = ""
        type.comment = "<b><em> Derived Type </em></b> :: <tt></tt>\n"
        type.comment << args_comment if args_comment
        type.comment << type_comment if type_comment
        progress "t"
        @stats.num_methods += 1
        container.add_method type

        set_visibility(container, typename, visibility_default, @@public_methods)

        if type_visibility
          type_visibility.gsub!(/\s/,'')
          type_visibility.gsub!(/\,/,'')
          type_visibility.gsub!(/:/,'')
          type_visibility.downcase!
          if type_visibility == "public"
            container.set_visibility_for([typename], :public)
          elsif type_visibility == "private"
            container.set_visibility_for([typename], :private)
          end
        end

        check_public_methods(type, container.name)

        if @options.show_all
          derived_types_comment << ", " unless derived_types_comment.empty?
          derived_types_comment << typename
        else
          if type.visibility == :public
          derived_types_comment << ", " unless derived_types_comment.empty?
          derived_types_comment << typename
          end
        end

      end

      if !derived_types_comment.empty?
        derived_types_table = 
          Attr.new("Derived Types", "Derived_Types", "", 
                   derived_types_comment)
        container.add_attribute(derived_types_table)
      end

      #
      # move interface scope
      #
      interface_code = ""
      while remaining_code =~ /^\s*?
                                   interface(
                                              \s+\w+                      |
                                              \s+operator\s*?\(.*?\)       |
                                              \s+assignment\s*?\(\s*?=\s*?\)
                                            )?\s*?$
                                   (.*?)
                                   ^\s*?end\s+interface.*?$
                              /imx
        interface_code << remove_empty_head_lines($&) + "\n"
        remaining_code = $~.pre_match
        remaining_code << $~.post_match
      end

      #
      # Parse global constants or variables in modules
      #
      const_var_defs = definition_info(before_contains_code)
      const_var_defs.each{|defitem|
        next if defitem.nodoc
        const_or_var_type = "Variable"
        const_or_var_progress = "v"
        if defitem.include_attr?("parameter")
          const_or_var_type = "Constant"
          const_or_var_progress = "c"
        end
        const_or_var = AnyMethod.new(const_or_var_type, defitem.varname)
        const_or_var.singleton = false
        const_or_var.params = ""
        self_comment = find_arguments([defitem.varname], before_contains_code)
        const_or_var.comment = "<b><em>" + const_or_var_type + "</em></b> :: <tt></tt>\n"
        const_or_var.comment << self_comment if self_comment
        progress const_or_var_progress
        @stats.num_methods += 1
        container.add_method const_or_var

        set_visibility(container, defitem.varname, visibility_default, @@public_methods)

        if defitem.include_attr?("public")
          container.set_visibility_for([defitem.varname], :public)
        elsif defitem.include_attr?("private")
          container.set_visibility_for([defitem.varname], :private)
        end

        check_public_methods(const_or_var, container.name)

      } if const_var_defs

      remaining_lines = remaining_code.split("\n")

      # "subroutine" or "function" parts are parsed (new)
      #
      level_depth = 0
      block_searching_flag = nil
      block_searching_lines = []
      pre_comment = []
      procedure_trailing = ""
      procedure_name = ""
      procedure_params = ""
      procedure_prefix = ""
      procedure_result_arg = ""
      procedure_type = ""
      contains_lines = []
      contains_flag = nil
      remaining_lines.collect!{|line|
        if !block_searching_flag
          # subroutine
          if line =~ /^\s*?
                           (recursive|pure|elemental)?\s*?
                           subroutine\s+(\w+)\s*?(\(.*?\))?\s*?(!.*?)?$
                     /ix
            block_searching_flag = :subroutine
            block_searching_lines << line

            procedure_name = $2.chomp.strip
            procedure_params = $3 || ""
            procedure_prefix = $1 || ""
            procedure_trailing = $4 || "!"
            next false

          # function
          elsif line =~ /^\s*?
                         (recursive|pure|elemental)?\s*?
                         (
                             character\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                           | type\s*?\([\w\s]+?\)\s+
                           | integer\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                           | real\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                           | double\s+precision\s+
                           | logical\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                           | complex\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                         )?
                         function\s+(\w+)\s*?
                         (\(.*?\))?(\s+result\((.*?)\))?\s*?(!.*?)?$
                        /ix
            block_searching_flag = :function
            block_searching_lines << line

            procedure_prefix = $1 || ""
            procedure_type = $2 ? $2.chomp.strip : nil
            procedure_name = $8.chomp.strip
            procedure_params = $9 || ""
            procedure_result_arg = $11 ? $11.chomp.strip : procedure_name
            procedure_trailing = $12 || "!"
            next false
          elsif line =~ /^\s*?!\s?(.*)/
            pre_comment << line
            next line
          else
            pre_comment = []
            next line
          end
        end
        contains_flag = true if line =~ /^\s*?contains\s*?(!.*?)?$/
        block_searching_lines << line
        contains_lines << line if contains_flag

        level_depth += 1 if block_start?(line)
        level_depth -= 1 if block_end?(line)
        if level_depth >= 0
          next false
        end

        # "procedure_code" is formatted.
        # ":nodoc:" flag is checked.
        #
        procedure_code = block_searching_lines.join("\n")
        procedure_code = remove_empty_head_lines(procedure_code)
        if procedure_trailing =~ /^!:nodoc:/
          # next loop to search next block
          level_depth = 0
          block_searching_flag = nil
          block_searching_lines = []
          pre_comment = []
          procedure_trailing = ""
          procedure_name = ""
          procedure_params = ""
          procedure_prefix = ""
          procedure_result_arg = ""
          procedure_type = ""
          contains_lines = []
          contains_flag = nil
          next false
        end

        # AnyMethod is created, and added to container
        #
        subroutine_function = nil
        if block_searching_flag == :subroutine
          subroutine_prefix   = procedure_prefix
          subroutine_name     = procedure_name
          subroutine_params   = procedure_params
          subroutine_trailing = procedure_trailing
          subroutine_code     = procedure_code

          subroutine_comment = COMMENTS_ARE_UPPER ? 
            pre_comment.join("\n") + "\n" + subroutine_trailing : 
              subroutine_trailing + "\n" + subroutine_code.sub(/^.*$\n/i, '')
          subroutine = AnyMethod.new("subroutine", subroutine_name)
          parse_subprogram(subroutine, subroutine_params,
                           subroutine_comment, subroutine_code,
                           before_contains_code, nil, subroutine_prefix)
          progress "s"
          @stats.num_methods += 1
          container.add_method subroutine
          subroutine_function = subroutine

        elsif block_searching_flag == :function
          function_prefix     = procedure_prefix
          function_type       = procedure_type
          function_name       = procedure_name
          function_params_org = procedure_params
          function_result_arg = procedure_result_arg
          function_trailing   = procedure_trailing
          function_code_org   = procedure_code

          function_comment = COMMENTS_ARE_UPPER ?
            pre_comment.join("\n") + "\n" + function_trailing :
              function_trailing + "\n " + function_code_org.sub(/^.*$\n/i, '')

          function_code = "#{function_code_org}"
          if function_type
            function_code << "\n" + function_type + " :: " + function_result_arg
          end

          function_params =
            function_params_org.sub(/^\(/, "\(#{function_result_arg}, ")

          function = AnyMethod.new("function", function_name)
          parse_subprogram(function, function_params,
                           function_comment, function_code,
                           before_contains_code, true, function_prefix)

          # Specific modification due to function
          function.params.sub!(/\(\s*?#{function_result_arg}\s*?,\s*?/, "\( ")
          function.params << " result(" + function_result_arg + ")"
          function.start_collecting_tokens
          function.add_token Token.new(1,1).set_text(function_code_org)

          progress "f"
          @stats.num_methods += 1
          container.add_method function
          subroutine_function = function

        end

        # The visibility of procedure is specified
        #
        set_visibility(container, procedure_name, 
                       visibility_default, @@public_methods)

        # The alias for this procedure from external modules
        #
        check_external_aliases(procedure_name,
                               subroutine_function.params,
                               subroutine_function.comment, subroutine_function) if external
        check_public_methods(subroutine_function, container.name)


        # contains_lines are parsed as private procedures
        if contains_flag
          parse_program_or_module(container,
                                  contains_lines.join("\n"), :private)
        end

        # next loop to search next block
        level_depth = 0
        block_searching_flag = nil
        block_searching_lines = []
        pre_comment = []
        procedure_trailing = ""
        procedure_name = ""
        procedure_params = ""
        procedure_prefix = ""
        procedure_result_arg = ""
        contains_lines = []
        contains_flag = nil
        next false
      } # End of remaining_lines.collect!{|line|

      # Array remains_lines is converted to String remains_code again
      #
      remaining_code = remaining_lines.join("\n")

      #
      # Parse interface
      #
      interface_scope = false
      generic_name = ""
      interface_code.split("\n").each{ |line|
        if /^\s*?
                 interface(
                            \s+\w+|
                            \s+operator\s*?\(.*?\)|
                            \s+assignment\s*?\(\s*?=\s*?\)
                          )?
                 \s*?(!.*?)?$
           /ix =~ line
          generic_name = $1 ? $1.strip.chomp : nil
          interface_trailing = $2 || "!"
          interface_scope = true
          interface_scope = false if interface_trailing =~ /!:nodoc:/
#          if generic_name =~ /operator\s*?\((.*?)\)/i
#            operator_name = $1
#            if operator_name && !operator_name.empty?
#              generic_name = "#{operator_name}"
#            end
#          end
#          if generic_name =~ /assignment\s*?\((.*?)\)/i
#            assignment_name = $1
#            if assignment_name && !assignment_name.empty?
#              generic_name = "#{assignment_name}"
#            end
#          end
        end
        if /^\s*?end\s+interface/i =~ line
          interface_scope = false
          generic_name = nil
        end
        # internal alias
        if interface_scope && /^\s*?module\s+procedure\s+(.*?)(!.*?)?$/i =~ line
          procedures = $1.strip.chomp
          procedures_trailing = $2 || "!"
          next if procedures_trailing =~ /!:nodoc:/
          procedures.split(",").each{ |proc|
            proc.strip!
            proc.chomp!
            next if generic_name == proc || !generic_name
            old_meth = container.find_symbol(proc, nil, @options.ignore_case)
            next if !old_meth
            nolink = old_meth.visibility == :private ? true : nil
            nolink = nil if @options.show_all
            new_meth = 
               initialize_external_method(generic_name, proc, 
                                          old_meth.params, nil, 
                                          old_meth.comment, 
                                          old_meth.clone.token_stream[0].text, 
                                          true, nolink)
            new_meth.singleton = old_meth.singleton

            progress "i"
            @stats.num_methods += 1
            container.add_method new_meth

            set_visibility(container, generic_name, visibility_default, @@public_methods)

            check_public_methods(new_meth, container.name)

          }
        end

        # external aliases
        if interface_scope
          # subroutine
          proc = nil
          params = nil
          procedures_trailing = nil
          if line =~ /^\s*?
                           (recursive|pure|elemental)?\s*?
                           subroutine\s+(\w+)\s*?(\(.*?\))?\s*?(!.*?)?$
                     /ix
            proc = $2.chomp.strip
            generic_name = proc unless generic_name
            params = $3 || ""
            procedures_trailing = $4 || "!"

          # function
          elsif line =~ /^\s*?
                         (recursive|pure|elemental)?\s*?
                         (
                             character\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                           | type\s*?\([\w\s]+?\)\s+
                           | integer\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                           | real\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                           | double\s+precision\s+
                           | logical\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                           | complex\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                         )?
                         function\s+(\w+)\s*?
                         (\(.*?\))?(\s+result\((.*?)\))?\s*?(!.*?)?$
                        /ix
            proc = $8.chomp.strip
            generic_name = proc unless generic_name
            params = $9 || ""
            procedures_trailing = $12 || "!"
          else
            next
          end
          next if procedures_trailing =~ /!:nodoc:/
          indicated_method = nil
          indicated_file   = nil
          TopLevel.all_files.each do |name, toplevel|
            indicated_method = toplevel.find_local_symbol(proc, @options.ignore_case)
            indicated_file = name
            break if indicated_method
          end

          if indicated_method
            external_method = 
              initialize_external_method(generic_name, proc, 
                                         indicated_method.params, 
                                         indicated_file, 
                                         indicated_method.comment)

            progress "e"
            @stats.num_methods += 1
            container.add_method external_method
            set_visibility(container, generic_name, visibility_default, @@public_methods)
            if !container.include_requires?(indicated_file, @options.ignore_case)
              container.add_require(Require.new(indicated_file, ""))
            end
            check_public_methods(external_method, container.name)

          else
            @@external_aliases << {
              "new_name"  => generic_name,
              "old_name"  => proc,
              "file_or_module" => container,
              "visibility" => find_visibility(container, generic_name, @@public_methods) || visibility_default
            }
          end
        end

      } if interface_code # End of interface_code.split("\n").each ...

      #
      # Already imported methods are removed from @@public_methods.
      # Remainders are assumed to be imported from other modules.
      #
      @@public_methods.delete_if{ |method| method["entity_is_discovered"]}

      @@public_methods.each{ |pub_meth|
        next unless pub_meth["file_or_module"].name == container.name
        pub_meth["used_modules"].each{ |used_mod|
          TopLevel.all_classes_and_modules.each{ |modules|
            if modules.name == used_mod ||
                modules.name.upcase == used_mod.upcase &&
                @options.ignore_case
              modules.method_list.each{ |meth|
                if meth.name == pub_meth["name"] ||
                    meth.name.upcase == pub_meth["name"].upcase &&
                    @options.ignore_case
                  new_meth = initialize_public_method(meth,
                                                      modules.name)
                  if pub_meth["local_name"]
                    new_meth.name = pub_meth["local_name"]
                  end
                  progress "e"
                  @stats.num_methods += 1
                  container.add_method new_meth
                end
              }
            end
          }
        }
      }

      container
    end  # End of parse_program_or_module

    #
    # Parse arguments, comment, code of subroutine and function.
    # Return AnyMethod object.
    #
    def parse_subprogram(subprogram, params, comment, code, 
                         before_contains=nil, function=nil, prefix=nil)
      subprogram.singleton = false
      prefix = "" if !prefix
      arguments = params.sub(/\(/, "").sub(/\)/, "").split(",") if params
      args_comment, params_opt = 
        find_arguments(arguments, code.sub(/^s*?contains\s*?(!.*?)?$.*/im, ""),
                       nil, nil, true)
      params_opt = "( " + params_opt + " ) " if params_opt
      subprogram.params = params_opt || ""
      namelist_comment = find_namelists(code, before_contains)

      block_comment = find_comments comment
      if function
        subprogram.comment = "<b><em> Function </em></b> :: <em>#{prefix}</em>\n"
      else
        subprogram.comment = "<b><em> Subroutine </em></b> :: <em>#{prefix}</em>\n"
      end
      subprogram.comment << args_comment if args_comment
      subprogram.comment << block_comment if block_comment
      subprogram.comment << namelist_comment if namelist_comment

      # For output source code
      subprogram.start_collecting_tokens
      subprogram.add_token Token.new(1,1).set_text(code)

      subprogram
    end

    #
    # Collect comment for file entity
    #
    def collect_first_comment(body)
      comment = ""
      not_comment = ""
      comment_start = false
      comment_end   = false
      body.split("\n").each{ |line|
        if comment_end
          not_comment << line
          not_comment << "\n"
        elsif /^\s*?!\s?(.*)$/i =~ line
          comment_start = true
          comment << $1
          comment << "\n"
        elsif /^\s*?$/i =~ line
          comment_end = true if comment_start && COMMENTS_ARE_UPPER
        else
          comment_end = true
          not_comment << line
          not_comment << "\n"
        end
      }
      return comment, not_comment
    end


    # Return comments of definitions of arguments
    #
    # If "all" argument is true, information of all arguments are returned.
    # If "modified_params" is true, list of arguments are decorated,
    # for example, optional arguments are parenthetic as "[arg]".
    #
    def find_arguments(args, text, all=nil, indent=nil, modified_params=nil)
      return unless args || all
      indent = "" unless indent
      args = ["all"] if all
      params = "" if modified_params
      comma = ""
      return unless text
      args_rdocforms = "\n"
      remaining_lines = "#{text}"
      definitions = definition_info(remaining_lines)
      args.each{ |arg|
        arg.strip!
        arg.chomp!
        definitions.each { |defitem|
          if arg == defitem.varname.strip.chomp || all
            args_rdocforms << <<-"EOF"

#{indent}<tt><b>#{defitem.varname.chomp.strip}#{defitem.arraysuffix}</b> #{defitem.inivalue}</tt> :: 
#{indent}   <tt>#{defitem.types.chomp.strip}</tt>
EOF
            if !defitem.comment.chomp.strip.empty?
              comment = ""
              defitem.comment.split("\n").each{ |line|
                comment << "       " + line + "\n"
              }
              args_rdocforms << <<-"EOF"

#{indent}   <tt></tt> :: 
#{indent}       <tt></tt>
#{indent}       #{comment.chomp.strip}
EOF
            end

            if modified_params
              if defitem.include_attr?("optional")
                params << "#{comma}[#{arg}]"
              else
                params << "#{comma}#{arg}"
              end
              comma = ", "
            end
          end
        }
      }
      if modified_params
        return args_rdocforms, params
      else
        return args_rdocforms
      end
    end

    # Return comments of definitions of namelists
    #
    def find_namelists(text, before_contains=nil)
      return nil if !text
      result = ""
      lines = "#{text}"
      before_contains = "" if !before_contains
      while lines =~ /^\s*?namelist\s+\/\s*?(\w+)\s*?\/([\s\w\,]+)$/i
        lines = $~.post_match
        nml_comment = COMMENTS_ARE_UPPER ? 
            find_comments($~.pre_match) : find_comments($~.post_match)
        nml_name = $1
        nml_args = $2.split(",")
        result << "\n\n=== NAMELIST <tt><b>" + nml_name + "</tt></b>\n\n"
        result << nml_comment + "\n" if nml_comment
        if lines.split("\n")[0] =~ /^\//i
          lines = "namelist " + lines
        end
        result << find_arguments(nml_args, "#{text}" + "\n" + before_contains)
      end
      return result
    end

    #
    # Comments just after module or subprogram, or arguments are
    # returned. If "COMMENTS_ARE_UPPER" is true, comments just before
    # modules or subprograms are returned
    #
    def find_comments text
      return "" unless text
      lines = text.split("\n")
      lines.reverse! if COMMENTS_ARE_UPPER
      comment_block = Array.new
      lines.each do |line|
        break if line =~ /^\s*?\w/ || line =~ /^\s*?$/
        if COMMENTS_ARE_UPPER
          comment_block.unshift line.sub(/^\s*?!\s?/,"")
        else
          comment_block.push line.sub(/^\s*?!\s?/,"")
        end
      end
      nice_lines = comment_block.join("\n").split "\n\s*?\n"
      nice_lines[0] ||= ""
      nice_lines.shift
    end

    def progress(char)
      unless @options.quiet
        @progress.print(char)
        @progress.flush
      end
    end

    #
    # Create method for internal alias
    #
    def initialize_public_method(method, parent)
      return if !method || !parent

      new_meth = AnyMethod.new("External Alias for module", method.name)
      new_meth.singleton    = method.singleton
      new_meth.params       = method.params.clone
      new_meth.comment      = remove_trailing_alias(method.comment.clone)
      new_meth.comment      << "\n\n#{EXTERNAL_ALIAS_MES} #{parent.strip.chomp}\##{method.name}"

      return new_meth
    end

    #
    # Create method for external alias
    #
    # If argument "internal" is true, file is ignored.
    #
    def initialize_external_method(new, old, params, file, comment, token=nil,
                                   internal=nil, nolink=nil)
      return nil unless new || old

      if internal
        external_alias_header = "#{INTERNAL_ALIAS_MES} "
        external_alias_text   = external_alias_header + old 
      elsif file
        external_alias_header = "#{EXTERNAL_ALIAS_MES} "
        external_alias_text   = external_alias_header + file + "#" + old
      else
        return nil
      end
      external_meth = AnyMethod.new(external_alias_text, new)
      external_meth.singleton    = false
      external_meth.params       = params
      external_comment = remove_trailing_alias(comment) + "\n\n" if comment
      external_meth.comment = external_comment || ""
      if nolink && token
        external_meth.start_collecting_tokens
        external_meth.add_token Token.new(1,1).set_text(token)
      else
        external_meth.comment << external_alias_text
      end

      return external_meth
    end



    #
    # Parse visibility
    #
    def parse_visibility(code, default, container)
      result = []
      visibility_default = default || :public

      used_modules = []
      container.includes.each{|i| used_modules << i.name} if container

      remaining_code = code.gsub(/^\s*?type[\s\,]+.*?\s+end\s+type.*?$/im, "")
      remaining_code.split("\n").each{ |line|
        if /^\s*?private\s*?$/ =~ line
          visibility_default = :private
          break
        end
      } if remaining_code

      remaining_code.split("\n").each{ |line|
        if /^\s*?private\s*?(::)?\s+(.*)\s*?(!.*?)?/i =~ line
          methods = $2.sub(/!.*$/, '')
          methods.split(",").each{ |meth|
            meth.sub!(/!.*$/, '')
            meth.gsub!(/:/, '')
            result << {
              "name" => meth.chomp.strip,
              "visibility" => :private,
              "used_modules" => used_modules.clone,
              "file_or_module" => container,
              "entity_is_discovered" => nil,
              "local_name" => nil
            }
          }
        elsif /^\s*?public\s*?(::)?\s+(.*)\s*?(!.*?)?/i =~ line
          methods = $2.sub(/!.*$/, '')
          methods.split(",").each{ |meth|
            meth.sub!(/!.*$/, '')
            meth.gsub!(/:/, '')
            result << {
              "name" => meth.chomp.strip,
              "visibility" => :public,
              "used_modules" => used_modules.clone,
              "file_or_module" => container,
              "entity_is_discovered" => nil,
              "local_name" => nil
            }
          }
        end
      } if remaining_code

      if container
        result.each{ |vis_info|
          vis_info["parent"] = container.name
        }
      end

      return visibility_default, result
    end

    #
    # Set visibility
    #
    # "subname" element of "visibility_info" is deleted.
    #
    def set_visibility(container, subname, visibility_default, visibility_info)
      return unless container || subname || visibility_default || visibility_info
      not_found = true
      visibility_info.collect!{ |info|
        if info["name"] == subname ||
            @options.ignore_case && info["name"].upcase == subname.upcase
          if info["file_or_module"].name == container.name
            container.set_visibility_for([subname], info["visibility"])
            info["entity_is_discovered"] = true
            not_found = false
          end
        end
        info
      }
      if not_found
        return container.set_visibility_for([subname], visibility_default)
      else
        return container
      end
    end

    #
    # Find visibility
    #
    def find_visibility(container, subname, visibility_info)
      return nil if !subname || !visibility_info
      visibility_info.each{ |info|
        if info["name"] == subname ||
            @options.ignore_case && info["name"].upcase == subname.upcase
          if info["parent"] == container.name
            return info["visibility"]
          end
        end
      }
      return nil
    end

    #
    # Check external aliases
    #
    def check_external_aliases(subname, params, comment, test=nil)
      @@external_aliases.each{ |alias_item|
        if subname == alias_item["old_name"] ||
                    subname.upcase == alias_item["old_name"].upcase &&
                            @options.ignore_case

          new_meth = initialize_external_method(alias_item["new_name"], 
                                                subname, params, @file_name, 
                                                comment)
          new_meth.visibility = alias_item["visibility"]

          progress "e"
          @stats.num_methods += 1
          alias_item["file_or_module"].add_method(new_meth)

          if !alias_item["file_or_module"].include_requires?(@file_name, @options.ignore_case)
            alias_item["file_or_module"].add_require(Require.new(@file_name, ""))
          end
        end
      }
    end

    #
    # Check public_methods
    #
    def check_public_methods(method, parent)
      return if !method || !parent
      @@public_methods.each{ |alias_item|
        parent_is_used_module = nil
        alias_item["used_modules"].each{ |used_module|
          if used_module == parent ||
              used_module.upcase == parent.upcase &&
              @options.ignore_case
            parent_is_used_module = true
          end
        }
        next if !parent_is_used_module

        if method.name == alias_item["name"] ||
            method.name.upcase == alias_item["name"].upcase &&
            @options.ignore_case

          new_meth = initialize_public_method(method, parent)
          if alias_item["local_name"]
            new_meth.name = alias_item["local_name"]
          end

          progress "e"
          @stats.num_methods += 1
          alias_item["file_or_module"].add_method new_meth
        end
      }
    end

    #
    # Continuous lines are united.
    #
    # Comments in continuous lines are removed.
    #
    def united_to_one_line(f90src)
      return "" unless f90src
      lines = f90src.split("\n")
      previous_continuing = false
      now_continuing = false
      body = ""
      lines.each{ |line|
        words = line.split("")
        next if words.empty? && previous_continuing
        commentout = false
        brank_flag = true ; brank_char = ""
        squote = false    ; dquote = false
        ignore = false
        words.collect! { |char|
          if previous_continuing && brank_flag
            now_continuing = true
            ignore         = true
            case char
            when "!"                       ; break
            when " " ; brank_char << char  ; next ""
            when "&"
              brank_flag = false
              now_continuing = false
              next ""
            else 
              brank_flag     = false
              now_continuing = false
              ignore         = false
              next brank_char + char
            end
          end
          ignore = false

          if now_continuing
            next ""
          elsif !(squote) && !(dquote) && !(commentout)
            case char
            when "!" ; commentout = true     ; next char
            when "\""; dquote = true         ; next char
            when "\'"; squote = true         ; next char
            when "&" ; now_continuing = true ; next ""
            else next char
            end
          elsif commentout
            next char
          elsif squote
            case char
            when "\'"; squote = false ; next char
            else next char
            end
          elsif dquote
            case char
            when "\""; dquote = false ; next char
            else next char
            end
          end
        }
        if !ignore && !previous_continuing || !brank_flag
          if previous_continuing
            body << words.join("")
          else
            body << "\n" + words.join("")
          end
        end
        previous_continuing = now_continuing ? true : nil
        now_continuing = nil
      }
      return body
    end


    #
    # Continuous line checker
    #
    def continuous_line?(line)
      continuous = false
      if /&\s*?(!.*)?$/ =~ line
        continuous = true
        if comment_out?($~.pre_match)
          continuous = false
        end
      end
      return continuous
    end

    #
    # Comment out checker
    #
    def comment_out?(line)
      return nil unless line
      commentout = false
      squote = false ; dquote = false
      line.split("").each { |char|
        if !(squote) && !(dquote)
          case char
          when "!" ; commentout = true ; break
          when "\""; dquote = true
          when "\'"; squote = true
          else next
          end
        elsif squote
          case char
          when "\'"; squote = false
          else next
          end
        elsif dquote
          case char
          when "\""; dquote = false
          else next
          end
        end
      }
      return commentout
    end

    #
    # Semicolons are replaced to line feed.
    #
    def semicolon_to_linefeed(text)
      return "" unless text
      lines = text.split("\n")
      lines.collect!{ |line|
        words = line.split("")
        commentout = false
        squote = false ; dquote = false
        words.collect! { |char|
          if !(squote) && !(dquote) && !(commentout)
            case char
            when "!" ; commentout = true ; next char
            when "\""; dquote = true     ; next char
            when "\'"; squote = true     ; next char
            when ";" ;                     "\n"
            else next char
            end
          elsif commentout
            next char
          elsif squote
            case char
            when "\'"; squote = false ; next char
            else next char
            end
          elsif dquote
            case char
            when "\""; dquote = false ; next char
            else next char
            end
          end
        }
        words.join("")
      }
      return lines.join("\n")
    end

    #
    # Which "line" is start of block (module, program, block data,
    # subroutine, function) statement ?
    #
    def block_start?(line)
      return nil if !line

      if line =~ /^\s*?module\s+(\w+)\s*?(!.*?)?$/i    ||
          line =~ /^\s*?program\s+(\w+)\s*?(!.*?)?$/i  ||
          line =~ /^\s*?block\s+data(\s+\w+)?\s*?(!.*?)?$/i     ||
          line =~ \
                  /^\s*?
                   (recursive|pure|elemental)?\s*?
                   subroutine\s+(\w+)\s*?(\(.*?\))?\s*?(!.*?)?$
                  /ix ||
          line =~ \
                  /^\s*?
                   (recursive|pure|elemental)?\s*?
                   (
                       character\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                     | type\s*?\([\w\s]+?\)\s+
                     | integer\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                     | real\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                     | double\s+precision\s+
                     | logical\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                     | complex\s*?(\([\w\s\=\(\)\*]+?\))?\s+
                   )?
                   function\s+(\w+)\s*?
                   (\(.*?\))?(\s+result\((.*?)\))?\s*?(!.*?)?$
                  /ix
        return true
      end

      return nil
    end

    #
    # Which "line" is end of block (module, program, block data,
    # subroutine, function) statement ?
    #
    def block_end?(line)
      return nil if !line

      if line =~ /^\s*?end\s*?(!.*?)?$/i                 ||
          line =~ /^\s*?end\s+module(\s+\w+)?\s*?(!.*?)?$/i       ||
          line =~ /^\s*?end\s+program(\s+\w+)?\s*?(!.*?)?$/i      ||
          line =~ /^\s*?end\s+block\s+data(\s+\w+)?\s*?(!.*?)?$/i  ||
          line =~ /^\s*?end\s+subroutine(\s+\w+)?\s*?(!.*?)?$/i   ||
          line =~ /^\s*?end\s+function(\s+\w+)?\s*?(!.*?)?$/i
        return true
      end

      return nil
    end

    #
    # Remove "Alias for" in end of comments
    #
    def remove_trailing_alias(text)
      return "" if !text
      lines = text.split("\n").reverse
      comment_block = Array.new
      checked = false
      lines.each do |line|
        if !checked 
          if /^\s?#{INTERNAL_ALIAS_MES}/ =~ line ||
              /^\s?#{EXTERNAL_ALIAS_MES}/ =~ line
            checked = true
            next
          end
        end
        comment_block.unshift line
      end
      nice_lines = comment_block.join("\n")
      nice_lines ||= ""
      return nice_lines
    end

    # Empty lines in header are removed
    def remove_empty_head_lines(text)
      return "" unless text
      lines = text.split("\n")
      header = true
      lines.delete_if{ |line|
        header = false if /\S/ =~ line
        header && /^\s*?$/ =~ line
      }
      lines.join("\n")
    end


    # header marker "=", "==", ... are removed
    def remove_header_marker(text)
      return text.gsub(/^\s?(=+)/, '<tt></tt>\1')
    end

    def remove_private_comments(body)
      body.gsub!(/^\s*!--\s*?$.*?^\s*!\+\+\s*?$/m, '')
      return body
    end


    #
    # Information of arguments of subroutines and functions in Fortran95
    #
    class Fortran95Definition

      # Name of variable
      #
      attr_reader   :varname

      # Types of variable
      #
      attr_reader   :types

      # Initial Value
      #
      attr_reader   :inivalue

      # Suffix of array
      #
      attr_reader   :arraysuffix

      # Comments
      #
      attr_accessor   :comment

      # Flag of non documentation
      #
      attr_accessor   :nodoc

      def initialize(varname, types, inivalue, arraysuffix, comment,
                     nodoc=false)
        @varname = varname
        @types = types
        @inivalue = inivalue
        @arraysuffix = arraysuffix
        @comment = comment
        @nodoc = nodoc
      end

      def to_s
        return <<-EOF
<Fortran95Definition: 
  varname=#{@varname}, types=#{types},
  inivalue=#{@inivalue}, arraysuffix=#{@arraysuffix}, nodoc=#{@nodoc}, 
  comment=
#{@comment}
>
EOF
      end

      #
      # If attr is included, true is returned
      #
      def include_attr?(attr)
        return if !attr
        @types.split(",").each{ |type|
          return true if type.strip.chomp.upcase == attr.strip.chomp.upcase
        }
        return nil
      end

    end # End of Fortran95Definition

    #
    # Parse string argument "text", and Return Array of
    # Fortran95Definition object
    #
    def definition_info(text)
      return nil unless text
      lines = "#{text}"
      defs = Array.new
      comment = ""
      trailing_comment = ""
      under_comment_valid = false
      lines.split("\n").each{ |line|
        if /^\s*?!\s?(.*)/ =~ line
          if COMMENTS_ARE_UPPER
            comment << remove_header_marker($1)
            comment << "\n"
          elsif defs[-1] && under_comment_valid
            defs[-1].comment << "\n"
            defs[-1].comment << remove_header_marker($1)
          end
          next
        elsif /^\s*?$/ =~ line
          comment = ""
          under_comment_valid = false
          next
        end
        type = ""
        characters = ""
        if line =~ /^\s*?
                    (
                        character\s*?(\([\w\s\=\(\)\*]+?\))?[\s\,]*
                      | type\s*?\([\w\s]+?\)[\s\,]*
                      | integer\s*?(\([\w\s\=\(\)\*]+?\))?[\s\,]*
                      | real\s*?(\([\w\s\=\(\)\*]+?\))?[\s\,]*
                      | double\s+precision[\s\,]*
                      | logical\s*?(\([\w\s\=\(\)\*]+?\))?[\s\,]*
                      | complex\s*?(\([\w\s\=\(\)\*]+?\))?[\s\,]*
                    )
                    (.*?::)?
                    (.+)$
                   /ix
          characters = $8
          type = $1
          type << $7.gsub(/::/, '').gsub(/^\s*?\,/, '') if $7
        else
          under_comment_valid = false
          next
        end
        squote = false ; dquote = false ; bracket = 0
        iniflag = false; commentflag = false
        varname = "" ; arraysuffix = "" ; inivalue = ""
        start_pos = defs.size
        characters.split("").each { |char|
          if !(squote) && !(dquote) && bracket <= 0 && !(iniflag) && !(commentflag)
            case char
            when "!" ; commentflag = true
            when "(" ; bracket += 1       ; arraysuffix = char
            when "\""; dquote = true
            when "\'"; squote = true
            when "=" ; iniflag = true     ; inivalue << char
            when ","
              defs << Fortran95Definition.new(varname, type, inivalue, arraysuffix, comment)
              varname = "" ; arraysuffix = "" ; inivalue = ""
              under_comment_valid = true
            when " " ; next
            else     ; varname << char
            end
          elsif commentflag
            comment << remove_header_marker(char)
            trailing_comment << remove_header_marker(char)
          elsif iniflag
            if dquote
              case char
              when "\"" ; dquote = false ; inivalue << char
              else      ; inivalue << char
              end
            elsif squote
              case char
              when "\'" ; squote = false ; inivalue << char
              else      ; inivalue << char
              end
            elsif bracket > 0
              case char
              when "(" ; bracket += 1 ; inivalue << char
              when ")" ; bracket -= 1 ; inivalue << char
              else     ; inivalue << char
              end
            else
              case char
              when ","
                defs << Fortran95Definition.new(varname, type, inivalue, arraysuffix, comment)
                varname = "" ; arraysuffix = "" ; inivalue = ""
                iniflag = false
                under_comment_valid = true
              when "(" ; bracket += 1 ; inivalue << char
              when "\""; dquote = true  ; inivalue << char
              when "\'"; squote = true  ; inivalue << char
              when "!" ; commentflag = true
              else     ; inivalue << char
              end
            end
          elsif !(squote) && !(dquote) && bracket > 0
            case char
            when "(" ; bracket += 1 ; arraysuffix << char
            when ")" ; bracket -= 1 ; arraysuffix << char
            else     ; arraysuffix << char
            end
          elsif squote
            case char
            when "\'"; squote = false ; inivalue << char
            else     ; inivalue << char
            end
          elsif dquote
            case char
            when "\""; dquote = false ; inivalue << char
            else     ; inivalue << char
            end
          end
        }
        defs << Fortran95Definition.new(varname, type, inivalue, arraysuffix, comment)
        if trailing_comment =~ /^:nodoc:/
          defs[start_pos..-1].collect!{ |defitem|
            defitem.nodoc = true
          }
        end
        varname = "" ; arraysuffix = "" ; inivalue = ""
        comment = ""
        under_comment_valid = true
        trailing_comment = ""
      }
      return defs
    end


  end # class Fortran95parser

end # module RDoc
