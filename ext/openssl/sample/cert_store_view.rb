#!/usr/bin/env ruby

require 'fox'
require 'openssl'
require 'time'
require 'certstore'
require 'getopts'

include Fox

module CertDumpSupport
  def cert_label(cert)
    subject_alt_name =
      cert.extensions.find { |ext| ext.oid == 'subjectAltName' }
    if subject_alt_name
      subject_alt_name.value.split(/\s*,\s/).each do |alt_name_pair|
	alt_tag, alt_name = alt_name_pair.split(/:/)
	return alt_name
      end
    end
    name_label(cert.subject)
  end

  def name_label(name)
    ary = name.to_a
    if (cn = ary.find { |rdn| rdn[0] == 'CN' })
      return cn[1]
    end
    if ary.last[0] == 'OU'
      return ary.last[1]
    end
    name.to_s
  end

  def name_text(name)
    name.to_a.collect { |tag, value|
      "#{tag} = #{value}"
    }.reverse.join("\n")
  end

  def bn_label(bn)
    ("0" << sprintf("%X", bn)).scan(/../).join(" ")
  end
end

class CertDump
  include CertDumpSupport

  def initialize(cert)
    @cert = cert
  end

  def get_dump(tag)
    case tag
    when 'Version'
      version
    when 'Serial'
      serial
    when 'Signature Algorithm'
      signature_algorithm
    when 'Issuer'
      issuer
    when 'Validity'
      validity
    when 'Not before'
      not_before
    when 'Not after'
      not_after
    when 'Subject'
      subject
    when 'Public key'
      public_key
    else
      ext(tag)
    end
  end

  def get_dump_line(tag)
    case tag
    when 'Version'
      version_line
    when 'Serial'
      serial_line
    when 'Signature Algorithm'
      signature_algorithm_line
    when 'Subject'
      subject_line
    when 'Issuer'
      issuer_line
    when 'Validity'
      validity_line
    when 'Not before'
      not_before_line
    when 'Not after'
      not_after_line
    when 'Public key'
      public_key_line
    else
      ext_line(tag)
    end
  end

private

  def version
    "Version: #{@cert.version + 1}"
  end

  def version_line
    version
  end

  def serial
    bn_label(@cert.serial)
  end

  def serial_line
    serial
  end

  def signature_algorithm
    @cert.signature_algorithm
  end

  def signature_algorithm_line
    signature_algorithm
  end

  def subject
    name_text(@cert.subject)
  end

  def subject_line
    @cert.subject.to_s
  end

  def issuer
    name_text(@cert.issuer)
  end

  def issuer_line
    @cert.issuer.to_s
  end

  def validity
    <<EOS
Not before: #{not_before}
Not after: #{not_after}
EOS
  end

  def validity_line
    "from #{@cert.not_before.iso8601} to #{@cert.not_after.iso8601}"
  end

  def not_before
    @cert.not_before.to_s
  end

  def not_before_line
    not_before
  end

  def not_after
    @cert.not_after.to_s
  end

  def not_after_line
    not_after
  end

  def public_key
    @cert.public_key.to_text
  end

  def public_key_line
    "#{@cert.public_key.class} -- " << public_key.scan(/\A[^\n]*/)[0] << '...'
  end

  def ext(tag)
    @cert.extensions.each do |ext|
      if ext.oid == tag
	return ext_detail(tag, ext.value)
      end
    end
    "(unknown)"
  end

  def ext_line(tag)
    ext(tag).tr("\r\n", '')
  end

  def ext_detail(tag, value)
    value
  end
end

class CrlDump
  include CertDumpSupport

  def initialize(crl)
    @crl = crl
  end

  def get_dump(tag)
    case tag
    when 'Version'
      version
    when 'Signature Algorithm'
      signature_algorithm
    when 'Issuer'
      issuer
    when 'Last update'
      last_update
    when 'Next update'
      next_update
    else
      ext(tag)
    end
  end

  def get_dump_line(tag)
    case tag
    when 'Version'
      version_line
    when 'Signature Algorithm'
      signature_algorithm_line
    when 'Issuer'
      issuer_line
    when 'Last update'
      last_update_line
    when 'Next update'
      next_update_line
    else
      ext_line(tag)
    end
  end

private

  def version
    "Version: #{@crl.version + 1}"
  end

  def version_line
    version
  end

  def signature_algorithm
    @crl.signature_algorithm
  end

  def signature_algorithm_line
    signature_algorithm
  end

  def issuer
    name_text(@crl.issuer)
  end

  def issuer_line
    @crl.issuer.to_s
  end

  def last_update
    @crl.last_update.to_s
  end

  def last_update_line
    last_update
  end

  def next_update
    @crl.next_update.to_s
  end

  def next_update_line
    next_update
  end

  def ext(tag)
    @crl.extensions.each do |ext|
      if ext.oid == tag
	return ext_detail(tag, ext.value)
      end
    end
    "(unknown)"
  end

  def ext_line(tag)
    ext(tag).tr("\r\n", '')
  end

  def ext_detail(tag, value)
    value
  end
end

class RevokedDump
  include CertDumpSupport

  def initialize(revoked)
    @revoked = revoked
  end

  def get_dump(tag)
    case tag
    when 'Serial'
      serial
    when 'Time'
      time
    else
      ext(tag)
    end
  end

  def get_dump_line(tag)
    case tag
    when 'Serial'
      serial_line
    when 'Time'
      time_line
    else
      ext_line(tag)
    end
  end

private

  def serial
    bn_label(@revoked.serial)
  end

  def serial_line
    serial
  end

  def time
    @revoked.time.to_s
  end

  def time_line
    time
  end

  def ext(tag)
    @revoked.extensions.each do |ext|
      if ext.oid == tag
	return ext_detail(tag, ext.value)
      end
    end
    "(unknown)"
  end

  def ext_line(tag)
    ext(tag).tr("\r\n", '')
  end

  def ext_detail(tag, value)
    value
  end
end

class RequestDump
  include CertDumpSupport

  def initialize(req)
    @req = req
  end

  def get_dump(tag)
    case tag
    when 'Version'
      version
    when 'Signature Algorithm'
      signature_algorithm
    when 'Subject'
      subject
    when 'Public key'
      public_key
    else
      attributes(tag)
    end
  end

  def get_dump_line(tag)
    case tag
    when 'Version'
      version_line
    when 'Signature Algorithm'
      signature_algorithm_line
    when 'Subject'
      subject_line
    when 'Public key'
      public_key_line
    else
      attributes_line(tag)
    end
  end

private

  def version
    "Version: #{@req.version + 1}"
  end

  def version_line
    version
  end

  def signature_algorithm
    @req.signature_algorithm
  end

  def signature_algorithm_line
    signature_algorithm
  end

  def subject
    name_text(@req.subject)
  end

  def subject_line
    @req.subject.to_s
  end

  def public_key
    @req.public_key.to_text
  end

  def public_key_line
    "#{@req.public_key.class} -- " << public_key.scan(/\A[^\n]*/)[0] << '...'
  end

  def attributes(tag)
    "(unknown)"
  end

  def attributes_line(tag)
    attributes(tag).tr("\r\n", '')
  end
end

class CertStoreView < FXMainWindow
  class CertTree
    include CertDumpSupport

    def initialize(observer, tree)
      @observer = observer
      @tree = tree
      @tree.connect(SEL_COMMAND) do |sender, sel, item|
       	if item.data
  	  @observer.getApp().beginWaitCursor do
  	    @observer.show_item(item.data)
  	  end
	else
	  @observer.show_item(nil)
  	end
      end
    end

    def show(cert_store)
      @tree.clearItems
      @self_signed_ca_node = add_item_last(nil, "Trusted root CA")
      @other_ca_node = add_item_last(nil, "Intermediate CA")
      @ee_node = add_item_last(nil, "Personal")
      @crl_node = add_item_last(nil, "CRL")
      @request_node = add_item_last(nil, "Request")
      @verify_path_node = add_item_last(nil, "Certification path")
      show_certs(cert_store)
    end

    def show_certs(cert_store)
      remove_items(@self_signed_ca_node)
      remove_items(@other_ca_node)
      remove_items(@ee_node)
      remove_items(@crl_node)
      remove_items(@request_node)
      import_certs(cert_store)
    end

    def show_request(req)
      node = add_item_last(@request_node, name_label(req.subject), req)
      @tree.selectItem(node)
      @observer.show_item(req)
    end

    def show_verify_path(verify_path)
      add_verify_path(verify_path)
    end

  private

    def open_node(node)
      node.expanded = node.opened = true
    end

    def close_node(node)
      node.expanded = node.opened = false
    end

    def import_certs(cert_store)
      cert_store.self_signed_ca.each do |cert|
	add_item_last(@self_signed_ca_node, cert_label(cert), cert)
      end
      cert_store.other_ca.each do |cert|
	add_item_last(@other_ca_node, cert_label(cert), cert)
      end
      cert_store.ee.each do |cert|
	add_item_last(@ee_node, cert_label(cert), cert)
      end
      cert_store.crl.each do |crl|
	node = add_item_last(@crl_node, name_label(crl.issuer), crl)
	close_node(node)
	crl.revoked.each do |revoked|
	  add_item_last(node, bn_label(revoked.serial), revoked)
	end
      end
      cert_store.request.each do |req|
	add_item_last(@requestnode, name_label(req.subject), req)
      end
    end

    def add_verify_path(verify_path)
      node = @verify_path_node
      last_cert = nil
      verify_path.reverse_each do |ok, cert, crl_check, error_string|
	warn = []
	if @observer.cert_store.is_ca?(cert)
	  warn << 'NO ARL' unless crl_check
	else
	  warn << 'NO CRL' unless crl_check
	end
	warn_str = '(' << warn.join(", ") << ')'
	warn_mark = warn.empty? ? '' : '!'
	label = if ok
	    "OK#{warn_mark}..." + cert_label(cert)
	  else
	    "NG(#{error_string})..." + cert_label(cert)
	  end
	label << warn_str unless warn.empty?
	node = add_item_last(node, label, cert)
	node.expanded = true
	last_cert = cert
      end
      if last_cert
	@tree.selectItem(node)
	@observer.show_item(last_cert)
      end
    end

    def add_item_last(parent, label, obj = nil)
      node = @tree.addItemLast(parent, FXTreeItem.new(label))
      node.data = obj if obj
      open_node(node)
      node
    end

    def remove_items(node)
      while node.getNumChildren > 0
	@tree.removeItem(node.getFirst)
      end
    end
  end

  class CertInfo
    def initialize(observer, table)
      @observer = observer
      @table = table
      @table.leadingRows = 0
      @table.leadingCols = 0
      @table.trailingRows = 0
      @table.trailingCols = 0
      @table.showVertGrid(false)
      @table.showHorzGrid(false)
      @table.setTableSize(1, 2)
      @table.setColumnWidth(0, 125)
      @table.setColumnWidth(1, 350)
    end

    def show(item)
      @observer.show_detail(nil, nil)
      if item.nil?
	set_column_size(1)
	return
      end
      case item
      when OpenSSL::X509::Certificate
	show_cert(item)
      when OpenSSL::X509::CRL
	show_crl(item)
      when OpenSSL::X509::Revoked
	show_revoked(item)
      when OpenSSL::X509::Request
	show_request(item)
      else
	raise NotImplementedError.new("Unknown item type #{item.class}.")
      end
    end

  private

    def show_cert(cert)
      wrap = CertDump.new(cert)
      items = []
      items << ['Version', wrap.get_dump_line('Version')]
      items << ['Signature Algorithm', wrap.get_dump_line('Signature Algorithm')]
      items << ['Issuer', wrap.get_dump_line('Issuer')]
      items << ['Serial', wrap.get_dump_line('Serial')]
      #items << ['Not before', wrap.get_dump_line('Not before')]
      #items << ['Not after', wrap.get_dump_line('Not after')]
      items << ['Subject', wrap.get_dump_line('Subject')]
      items << ['Public key', wrap.get_dump_line('Public key')]
      items << ['Validity', wrap.get_dump_line('Validity')]
      (cert.extensions.sort { |a, b| a.oid <=> b.oid }).each do |ext|
	items << [ext.oid, wrap.get_dump_line(ext.oid)]
      end
      show_items(cert, items)
    end

    def show_crl(crl)
      wrap = CrlDump.new(crl)
      items = []
      items << ['Version', wrap.get_dump_line('Version')]
      items << ['Signature Algorithm', wrap.get_dump_line('Signature Algorithm')]
      items << ['Issuer', wrap.get_dump_line('Issuer')]
      items << ['Last update', wrap.get_dump_line('Last update')]
      items << ['Next update', wrap.get_dump_line('Next update')]
      crl.extensions.each do |ext|
	items << [ext.oid, wrap.get_dump_line(ext.oid)]
      end
      show_items(crl, items)
    end

    def show_revoked(revoked)
      wrap = RevokedDump.new(revoked)
      items = []
      items << ['Serial', wrap.get_dump_line('Serial')]
      items << ['Time', wrap.get_dump_line('Time')]
      revoked.extensions.each do |ext|
	items << [ext.oid, wrap.get_dump_line(ext.oid)]
      end
      show_items(revoked, items)
    end

    def show_request(req)
      wrap = RequestDump.new(req)
      items = []
      items << ['Version', wrap.get_dump_line('Version')]
      items << ['Signature Algorithm', wrap.get_dump_line('Signature Algorithm')]
      items << ['Subject', wrap.get_dump_line('Subject')]
      items << ['Public key', wrap.get_dump_line('Public key')]
      req.attributes.each do |attr|
	items << [attr.attr, wrap.get_dump_line(attr.oid)]
      end
      show_items(req, items)
    end

    def show_items(obj, items)
      set_column_size(items.size)
      items.each_with_index do |ele, idx|
	tag, value = ele
	@table.setItemText(idx, 0, tag)
	@table.getItem(idx, 0).data = tag
	@table.setItemText(idx, 1, value.to_s)
	@table.getItem(idx, 1).data = tag
      end
      @table.connect(SEL_COMMAND) do |sender, sel, loc|
	item = @table.getItem(loc.row, loc.col)
	@observer.show_detail(obj, item.data)
      end
      justify_table
    end

    def set_column_size(size)
      col0_width = @table.getColumnWidth(0)
      col1_width = @table.getColumnWidth(1)
      @table.setTableSize(size, 2)
      @table.setColumnWidth(0, col0_width)
      @table.setColumnWidth(1, col1_width)
    end

    def justify_table
      for col in 0..@table.numCols-1
      	for row in 0..@table.numRows-1
  	  @table.getItem(row, col).justify = FXTableItem::LEFT
   	end
      end
    end
  end

  class CertDetail
    def initialize(observer, detail)
      @observer = observer
      @detail = detail
    end

    def show(item, tag)
      if item.nil?
	@detail.text = ''
	return
      end
      case item
      when OpenSSL::X509::Certificate
	show_cert(item, tag)
      when OpenSSL::X509::CRL
	show_crl(item, tag)
      when OpenSSL::X509::Revoked
	show_revoked(item, tag)
      when OpenSSL::X509::Request
	show_request(item, tag)
      else
	raise NotImplementedError.new("Unknown item type #{item.class}.")
      end
    end

  private

    def show_cert(cert, tag)
      wrap = CertDump.new(cert)
      @detail.text = wrap.get_dump(tag)
    end

    def show_crl(crl, tag)
      wrap = CrlDump.new(crl)
      @detail.text = wrap.get_dump(tag)
    end

    def show_revoked(revoked, tag)
      wrap = RevokedDump.new(revoked)
      @detail.text = wrap.get_dump(tag)
    end

    def show_request(request, tag)
      wrap = RequestDump.new(request)
      @detail.text = wrap.get_dump(tag)
    end
  end

  attr_reader :cert_store

  def initialize(app, cert_store)
    @cert_store = cert_store
    @verify_filter = 0
    @verify_filename = nil
    full_width = 800
    full_height = 500
    horz_pos = 300

    super(app, "Certificate store", nil, nil, DECOR_ALL, 0, 0, full_width,
      full_height)

    FXTooltip.new(self.getApp())

    menubar = FXMenubar.new(self, LAYOUT_SIDE_TOP|LAYOUT_FILL_X)
    file_menu = FXMenuPane.new(self)
    FXMenuTitle.new(menubar, "&File", nil, file_menu)
    file_open_menu = FXMenuPane.new(self)
    FXMenuCommand.new(file_open_menu, "&Directory\tCtl-O").connect(SEL_COMMAND,
      method(:on_cmd_file_open_dir))
    FXMenuCascade.new(file_menu, "&Open\tCtl-O", nil, file_open_menu)
    FXMenuCommand.new(file_menu, "&Quit\tCtl-Q", nil, getApp(), FXApp::ID_QUIT)

    tool_menu = FXMenuPane.new(self)
    FXMenuTitle.new(menubar, "&Tool", nil, tool_menu)
    FXMenuCommand.new(tool_menu, "&Verify\tCtl-N").connect(SEL_COMMAND,
      method(:on_cmd_tool_verify))
    FXMenuCommand.new(tool_menu, "&Show Request\tCtl-R").connect(SEL_COMMAND,
      method(:on_cmd_tool_request))

    base_frame = FXHorizontalFrame.new(self, LAYOUT_FILL_X | LAYOUT_FILL_Y)
    splitter_horz = FXSplitter.new(base_frame, LAYOUT_SIDE_TOP | LAYOUT_FILL_X |
    LAYOUT_FILL_Y | SPLITTER_TRACKING | SPLITTER_HORIZONTAL)

    # Cert tree
    cert_tree_frame = FXHorizontalFrame.new(splitter_horz, LAYOUT_FILL_X |
      LAYOUT_FILL_Y | FRAME_SUNKEN | FRAME_THICK)
    cert_tree_frame.setWidth(horz_pos)
    cert_tree = FXTreeList.new(cert_tree_frame, 0, nil, 0,
      TREELIST_BROWSESELECT | TREELIST_SHOWS_LINES | TREELIST_SHOWS_BOXES |
      TREELIST_ROOT_BOXES | LAYOUT_FILL_X | LAYOUT_FILL_Y)
    @cert_tree = CertTree.new(self, cert_tree)

    # Cert info
    splitter_vert = FXSplitter.new(splitter_horz, LAYOUT_SIDE_TOP |
      LAYOUT_FILL_X | LAYOUT_FILL_Y | SPLITTER_TRACKING | SPLITTER_VERTICAL |
      SPLITTER_REVERSED)
    cert_list_base = FXVerticalFrame.new(splitter_vert, LAYOUT_FILL_X |
      LAYOUT_FILL_Y, 0,0,0,0, 0,0,0,0)
    cert_list_frame = FXHorizontalFrame.new(cert_list_base, FRAME_SUNKEN |
      FRAME_THICK | LAYOUT_FILL_X | LAYOUT_FILL_Y)
    cert_info = FXTable.new(cert_list_frame, 2, 10, nil, 0, FRAME_SUNKEN |
      TABLE_COL_SIZABLE | LAYOUT_FILL_X | LAYOUT_FILL_Y, 0, 0, 0, 0, 2, 2, 2, 2)
    @cert_info = CertInfo.new(self, cert_info)

    cert_detail_base = FXVerticalFrame.new(splitter_vert, LAYOUT_FILL_X |
      LAYOUT_FILL_Y, 0,0,0,0, 0,0,0,0)
    cert_detail_frame = FXHorizontalFrame.new(cert_detail_base, FRAME_SUNKEN |
      FRAME_THICK | LAYOUT_FILL_X | LAYOUT_FILL_Y)
    cert_detail = FXText.new(cert_detail_frame, nil, 0, TEXT_READONLY |
      LAYOUT_FILL_X | LAYOUT_FILL_Y)
    @cert_detail = CertDetail.new(self, cert_detail)

    show_init
  end

  def create
    super
    show(PLACEMENT_SCREEN)
  end

  def show_init
    @cert_tree.show(@cert_store)
    show_item(nil)
  end

  def show_certs
    @cert_tree.show_certs(@cert_store)
  end

  def show_request(req)
    @cert_tree.show_request(req)
  end

  def show_verify_path(verify_path)
    @cert_tree.show_verify_path(verify_path)
  end

  def show_item(item)
    @cert_info.show(item) if @cert_info
  end

  def show_detail(item, tag)
    @cert_detail.show(item, tag) if @cert_detail
  end

  def verify(certfile)
    path = verify_certfile(certfile)
    show_certs	# CRL could be change.
    show_verify_path(path)
  end

private

  def on_cmd_file_open_dir(sender, sel, ptr)
    dir = FXFileDialog.getOpenDirectory(self, "Open certificate directory", ".")
    unless dir.empty?
      begin
	@cert_store = CertStore.new(dir)
      rescue
	show_error($!)
      end
      show_init
    end
    1
  end

  def on_cmd_tool_verify(sender, sel, ptr)
    dialog = FXFileDialog.new(self, "Verify certificate")
    dialog.filename = ''
    dialog.patternList = ["All Files (*)", "PEM formatted certificate (*.pem)"]
    dialog.currentPattern = @verify_filter
    if dialog.execute != 0
      @verify_filename = dialog.filename
      verify(@verify_filename)
    end
    @verify_filter = dialog.currentPattern
    1
  end

  def on_cmd_tool_request(sender, sel, ptr)
    dialog = FXFileDialog.new(self, "Show request")
    dialog.filename = ''
    dialog.patternList = ["All Files (*)", "PEM formatted certificate (*.pem)"]
    if dialog.execute != 0
      req = @cert_store.generate_cert(dialog.filename)
      show_request(req)
    end
    1
  end

  def verify_certfile(filename)
    begin
      cert = @cert_store.generate_cert(filename)
      result = @cert_store.verify(cert)
      @cert_store.scan_certs
      result
    rescue
      show_error($!)
      []
    end
  end

  def show_error(e)
    msg = e.inspect + "\n" + e.backtrace.join("\n")
    FXMessageBox.error(self, MBOX_OK, "Error", msg)
  end
end

getopts nil, "cert:"

certs_dir = ARGV.shift or raise "#{$0} cert_dir"
certfile = $OPT_cert
app = FXApp.new("CertStore", "FoxTest")
cert_store = CertStore.new(certs_dir)
w = CertStoreView.new(app, cert_store)
app.create
if certfile
  w.verify(certfile)
end
app.run
