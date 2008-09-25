require 'rdoc/generator/html'
require 'rdoc/generator/html/kilmerfactory'

module RDoc::Generator::HTML::HEFSS

  FONTS = "Verdana, Arial, Helvetica, sans-serif"

  CENTRAL_STYLE = <<-EOF
body,p { font-family: <%= values["fonts"] %>;
       color: #000040; background: #BBBBBB;
}

td { font-family: <%= values["fonts"] %>;
       color: #000040;
}

.attr-rw { font-size: small; color: #444488 }

.title-row {color:      #eeeeff;
	    background: #BBBBDD;
}

.big-title-font { color: white;
                  font-family: <%= values["fonts"] %>;
                  font-size: large;
                  height: 50px}

.small-title-font { color: purple;
                    font-family: <%= values["fonts"] %>;
                    font-size: small; }

.aqua { color: purple }

#diagram img {
  border: 0;
}

.method-name, attr-name {
      font-family: monospace; font-weight: bold;
}

.tablesubtitle {
   width: 100%;
   margin-top: 1ex;
   margin-bottom: .5ex;
   padding: 5px 0px 5px 20px;
   font-size: large;
   color: purple;
   background: #BBBBCC;
}

.tablesubsubtitle {
   width: 100%;
   margin-top: 1ex;
   margin-bottom: .5ex;
   padding: 5px 0px 5px 20px;
   font-size: medium;
   color: white;
   background: #BBBBCC;
}

.name-list {
  font-family: monospace;
  margin-left: 40px;
  margin-bottom: 2ex;
  line-height: 140%;
}

.description {
  margin-left: 40px;
  margin-bottom: 2ex;
  line-height: 140%;
}

.methodtitle {
  font-size: medium;
  text_decoration: none;
  padding: 3px 3px 3px 20px;
  color: #0000AA;
}

.ruby-comment    { color: green; font-style: italic }
.ruby-constant   { color: #4433aa; font-weight: bold; }
.ruby-identifier { color: #222222;  }
.ruby-ivar       { color: #2233dd; }
.ruby-keyword    { color: #3333FF; font-weight: bold }
.ruby-node       { color: #777777; }
.ruby-operator   { color: #111111;  }
.ruby-regexp     { color: #662222; }
.ruby-value      { color: #662222; font-style: italic }

.srcbut { float: right }
  EOF

  INDEX_STYLE = <<-EOF
body {
  background-color: #bbbbbb;
  font-family: #{FONTS};
  font-size: 11px;
  font-style: normal;
  line-height: 14px;
  color: #000040;
}

div.banner {
  background: #bbbbcc;
  color: white;
  padding: 1;
  margin: 0;
  font-size: 90%;
  font-weight: bold;
  line-height: 1.1;
  text-align: center;
  width: 100%;
}
EOF

  FACTORY = RDoc::Generator::HTML::
    KilmerFactory.new(:central_css => CENTRAL_STYLE,
                      :index_css => INDEX_STYLE,
                      :method_list_heading => "Subroutines and Functions",
                      :class_and_module_list_heading => "Classes and Modules",
                      :attribute_list_heading => "Arguments")

  STYLE = FACTORY.get_STYLE()

  METHOD_LIST = FACTORY.get_METHOD_LIST()
  
  BODY = FACTORY.get_BODY()
  
  FILE_PAGE = FACTORY.get_FILE_PAGE()

  CLASS_PAGE = FACTORY.get_CLASS_PAGE()

  SRC_PAGE = FACTORY.get_SRC_PAGE()

  FR_INDEX_BODY = FACTORY.get_FR_INDEX_BODY()

  FILE_INDEX = FACTORY.get_FILE_INDEX()

  CLASS_INDEX = FACTORY.get_CLASS_INDEX()

  METHOD_INDEX = FACTORY.get_METHOD_INDEX()

  INDEX = FACTORY.get_INDEX()

  def self.write_extra_pages(values)
    FACTORY.write_extra_pages(values)
  end
end
