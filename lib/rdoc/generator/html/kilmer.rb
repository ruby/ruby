require 'rdoc/generator/html'
require 'rdoc/generator/html/kilmerfactory'

module RDoc::Generator::HTML::KILMER

  FONTS = "Verdana, Arial, Helvetica, sans-serif"

  CENTRAL_STYLE = <<-EOF
body,td,p { font-family: <%= values["fonts"] %>;
       color: #000040;
}

.attr-rw { font-size: xx-small; color: #444488 }

.title-row { background-color: #CCCCFF;
             color:      #000010;
}

.big-title-font {
  color: black;
  font-weight: bold;
  font-family: <%= values["fonts"] %>;
  font-size: large;
  height: 60px;
  padding: 10px 3px 10px 3px;
}

.small-title-font { color: black;
                    font-family: <%= values["fonts"] %>;
                    font-size:10; }

.aqua { color: black }

#diagram img {
  border: 0;
}

.method-name, .attr-name {
      font-family: font-family: <%= values["fonts"] %>;
      font-weight: bold;
      font-size: small;
      margin-left: 20px;
      color: #000033;
}

.tablesubtitle, .tablesubsubtitle {
   width: 100%;
   margin-top: 1ex;
   margin-bottom: .5ex;
   padding: 5px 0px 5px 3px;
   font-size: large;
   color: black;
   background-color: #CCCCFF;
   border: thin;
}

.name-list {
  margin-left: 5px;
  margin-bottom: 2ex;
  line-height: 105%;
}

.description {
  margin-left: 5px;
  margin-bottom: 2ex;
  line-height: 105%;
  font-size: small;
}

.methodtitle {
  font-size: small;
  font-weight: bold;
  text-decoration: none;
  color: #000033;
  background: #ccc;
}

.srclink {
  font-size: small;
  font-weight: bold;
  text-decoration: none;
  color: #0000DD;
  background-color: white;
}

.srcbut { float: right }

.ruby-comment    { color: green; font-style: italic }
.ruby-constant   { color: #4433aa; font-weight: bold; }
.ruby-identifier { color: #222222;  }
.ruby-ivar       { color: #2233dd; }
.ruby-keyword    { color: #3333FF; font-weight: bold }
.ruby-node       { color: #777777; }
.ruby-operator   { color: #111111;  }
.ruby-regexp     { color: #662222; }
.ruby-value      { color: #662222; font-style: italic }
  EOF

  INDEX_STYLE = <<-EOF
body {
  background-color: #ddddff;
  font-family: #{FONTS};
  font-size: 11px;
  font-style: normal;
  line-height: 14px;
  color: #000040;
}

div.banner {
  background: #0000aa;
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
                      :index_css => INDEX_STYLE)

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
