#
#  [incr Widgets] support
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/itcl'
require 'tkextlib/itk'

# call setup script for general 'tkextlib' libraries
#require 'tkextlib/setup.rb'

# call setup script
#require 'tkextlib/iwidgets/setup.rb'

# load all image format handlers
#TkPackage.require('Iwidgets', '4.0')
TkPackage.require('Iwidgets')

module Tk
  module Iwidgets
    extend TkCore

    def self.package_version
      begin
	TkPackage.require('Iwidgets')
      rescue
	''
      end
    end

    ####################################################

    autoload :Buttonbox,             'tkextlib/iwidgets/buttonbox'
    autoload :Calendar,              'tkextlib/iwidgets/calendar'
    autoload :Canvasprintbox,        'tkextlib/iwidgets/canvasprintbox'
    autoload :Canvasprintdialog,     'tkextlib/iwidgets/canvasprintdialog'
    autoload :Checkbox,              'tkextlib/iwidgets/checkbox'
    autoload :Combobox,              'tkextlib/iwidgets/combobox'
    autoload :Dateentry,             'tkextlib/iwidgets/dateentry'
    autoload :Datefield,             'tkextlib/iwidgets/datefield'
    autoload :Dialog,                'tkextlib/iwidgets/dialog'
    autoload :Dialogshell,           'tkextlib/iwidgets/dialogshell'
    autoload :Disjointlistbox,       'tkextlib/iwidgets/disjointlistbox'
    autoload :Entryfield,            'tkextlib/iwidgets/entryfield'
    autoload :Extbutton,             'tkextlib/iwidgets/extbutton'
    autoload :Extfileselectionbox,   'tkextlib/iwidgets/extfileselectionbox'
    autoload :Extfileselectiondialog,'tkextlib/iwidgets/extfileselectiondialog'
    autoload :Feedback,              'tkextlib/iwidgets/feedback'
    autoload :Fileselectionbox,      'tkextlib/iwidgets/fileselectionbox'
    autoload :Fileselectiondialog,   'tkextlib/iwidgets/fileselectiondialog'
    autoload :Finddialog,            'tkextlib/iwidgets/finddialog'
    autoload :Hierarchy,             'tkextlib/iwidgets/hierarchy'
    autoload :Hyperhelp,             'tkextlib/iwidgets/hyperhelp'
    autoload :Labeledframe,          'tkextlib/iwidgets/labeledframe'
    autoload :Labeledwidget,         'tkextlib/iwidgets/labeledwidget'
    autoload :Mainwindow,            'tkextlib/iwidgets/mainwindow'
    autoload :Messagebox,            'tkextlib/iwidgets/messagebox'
    autoload :Messagedialog,         'tkextlib/iwidgets/messagedialog'
    autoload :Radiobox,              'tkextlib/iwidgets/radiobox'
    autoload :Scrolledwidget,        'tkextlib/iwidgets/scrolledwidget'
    autoload :Shell,                 'tkextlib/iwidgets/shell'
    autoload :Timeentry,             'tkextlib/iwidgets/timeentry'
    autoload :Timefield,             'tkextlib/iwidgets/timefield'
    autoload :Toolbar,               'tkextlib/iwidgets/toolbar'
    autoload :Watch,                 'tkextlib/iwidgets/watch'
  end
end
