#!/usr/local/bin/ruby
# Illustration of a script to convert an RDoc-style file to a LaTeX
# document

require 'rdoc/markup/simple_markup'
require 'rdoc/markup/simple_markup/to_latex'

p = SM::SimpleMarkup.new
h = SM::ToLaTeX.new

#puts "\\documentclass{report}"
#puts "\\usepackage{tabularx}"
#puts "\\usepackage{parskip}"
#puts "\\begin{document}"
puts p.convert(ARGF.read, h)
#puts "\\end{document}"
