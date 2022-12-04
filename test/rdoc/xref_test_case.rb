# frozen_string_literal: true
ENV['RDOC_TEST'] = 'yes'

require_relative 'helper'
require File.expand_path '../xref_data', __FILE__

class XrefTestCase < RDoc::TestCase

  def setup
    super

    @options = RDoc::Options.new
    @options.quiet = true

    @rdoc.options = @options

    @file_name = 'xref_data.rb'
    @xref_data = @store.add_file @file_name
    @top_level = @xref_data

    stats = RDoc::Stats.new @store, 0

    parser = RDoc::Parser::Ruby.new @xref_data, @file_name, XREF_DATA, @options,
                                    stats

    @example_md = @store.add_file 'EXAMPLE.md'
    @example_md.parser = RDoc::Parser::Markdown

    @top_levels = []
    @top_levels.push parser.scan
    @top_levels.push @example_md

    generator = Object.new
    def generator.class_dir() nil end
    def generator.file_dir() nil end
    @rdoc.options = @options
    @rdoc.generator = generator

    @c1       = @xref_data.find_module_named 'C1'
    @c1__m    = @c1.find_class_method_named 'm' # C1::m
    @c1_m     = @c1.find_instance_method_named 'm'  # C1#m
    @c1_plus  = @c1.find_instance_method_named '+'

    @c2    = @xref_data.find_module_named 'C2'
    @c2_a  = @c2.method_list.last
    @c2_b  = @c2.method_list.first

    @c2_c3 = @xref_data.find_module_named 'C2::C3'
    @c2_c3_m = @c2_c3.method_list.first # C2::C3#m

    @c2_c3_h1 = @xref_data.find_module_named 'C2::C3::H1'
    @c2_c3_h1_meh = @c2_c3_h1.method_list.first # C2::C3::H1#m?

    @c3    = @xref_data.find_module_named 'C3'
    @c4    = @xref_data.find_module_named 'C4'
    @c4_c4 = @xref_data.find_module_named 'C4::C4'
    @c5_c1 = @xref_data.find_module_named 'C5::C1'
    @c3_h1 = @xref_data.find_module_named 'C3::H1'
    @c3_h2 = @xref_data.find_module_named 'C3::H2'
    @c6    = @xref_data.find_module_named 'C6'
    @c7    = @xref_data.find_module_named 'C7'
    @c8    = @xref_data.find_module_named 'C8'
    @c8_s1 = @xref_data.find_module_named 'C8::S1'

    @c9         = @xref_data.find_module_named 'C9'
    @c9_a       = @xref_data.find_module_named 'C9::A'
    @c9_a_i_foo = @c9_a.method_list.first
    @c9_a_c_bar = @c9_a.method_list.last
    @c9_b       = @xref_data.find_module_named 'C9::B'
    @c9_b_c_foo = @c9_b.method_list.first
    @c9_b_i_bar = @c9_b.method_list.last

    @object         = @xref_data.find_module_named 'Object'
    @c10_class      = @xref_data.find_module_named 'C10'
    @c10_method     = @object.find_method_named 'C10'
    @c11_class      = @xref_data.find_module_named 'C11'
    @c10_c11_class  = @c10_class.find_module_named 'C11'
    @c10_c11_method = @c10_class.find_method_named 'C11'
    @c11_method     = @object.find_method_named 'C11'

    @m1    = @xref_data.find_module_named 'M1'
    @m1_m  = @m1.method_list.first

    @m1_m2 = @xref_data.find_module_named 'M1::M2'

    @parent = @xref_data.find_module_named 'Parent'
    @child  = @xref_data.find_module_named 'Child'

    @parent_m  = @parent.method_list.first # Parent#m
    @parent__m = @parent.method_list.last  # Parent::m
  end

end

