/************************************************

  gtk.c -

  $Author$
  $Date$
  created at: Wed Jan  7 23:55:11 JST 1998

************************************************/

#include "ruby.h"
#include "sig.h"
#include <gtk/gtk.h>
#include <signal.h>

extern VALUE rb_argv, rb_argv0;
extern VALUE cData;

static VALUE mGtk;

static VALUE gObject;
static VALUE gWidget;
static VALUE gContainer;
static VALUE gBin;
static VALUE gAlignment;
static VALUE gMisc;
static VALUE gArrow;
static VALUE gFrame;
static VALUE gAspectFrame;
static VALUE gData;
static VALUE gAdjustment;
static VALUE gBox;
static VALUE gButton;
static VALUE gTButton;
static VALUE gCButton;
static VALUE gRButton;
static VALUE gBBox;
static VALUE gCList;
static VALUE gWindow;
static VALUE gDialog;
static VALUE gFileSel;
static VALUE gVBox;
static VALUE gColorSel;
static VALUE gColorSelDialog;
static VALUE gImage;
static VALUE gDrawArea;
static VALUE gEntry;
static VALUE gEventBox;
static VALUE gFixed;
static VALUE gGamma;
static VALUE gHBBox;
static VALUE gVBBox;
static VALUE gHBox;
static VALUE gPaned;
static VALUE gHPaned;
static VALUE gVPaned;
static VALUE gRuler;
static VALUE gHRuler;
static VALUE gVRuler;
static VALUE gRange;
static VALUE gScale;
static VALUE gHScale;
static VALUE gVScale;
static VALUE gScrollbar;
static VALUE gHScrollbar;
static VALUE gVScrollbar;
static VALUE gSeparator;
static VALUE gHSeparator;
static VALUE gVSeparator;
static VALUE gInputDialog;
static VALUE gLabel;
static VALUE gList;
static VALUE gItem;
static VALUE gListItem;
static VALUE gMenuShell;
static VALUE gMenu;
static VALUE gMenuBar;
static VALUE gMenuItem;
static VALUE gCMenuItem;
static VALUE gRMenuItem;
static VALUE gNotebook;
static VALUE gOptionMenu;
static VALUE gPixmap;
static VALUE gPreview;
static VALUE gProgressBar;
static VALUE gScrolledWin;
static VALUE gTable;
static VALUE gText;
static VALUE gToolbar;
static VALUE gTooltips;
static VALUE gTree;
static VALUE gTreeItem;
static VALUE gViewPort;

static VALUE gAcceleratorTable;
static VALUE gStyle;
static VALUE gPreviewInfo;
static VALUE gAllocation;
static VALUE gRequisiton;

static VALUE mGdk;

static VALUE gdkFont;
static VALUE gdkColor;
static VALUE gdkColormap;
static VALUE gdkPixmap;
static VALUE gdkBitmap;
static VALUE gdkWindow;
static VALUE gdkImage;
static VALUE gdkVisual;
static VALUE gdkGC;
static VALUE gdkRectangle;
static VALUE gdkGCValues;
static VALUE gdkRectangle;
static VALUE gdkSegment;
static VALUE gdkWindowAttr;
static VALUE gdkCursor;
static VALUE gdkAtom;
static VALUE gdkColorContext;
static VALUE gdkEvent;

ID id_gtkdata, id_relatives, id_call, id_init;

static void gobj_free();

static GtkObject*
get_gobject(obj)
    VALUE obj;
{
    struct RData *data;
    GtkObject *gtkp;

    if (NIL_P(obj)) return NULL;

    Check_Type(obj, T_OBJECT);
    data = RDATA(rb_ivar_get(obj, id_gtkdata));
    if (NIL_P(data) || data->dfree != gobj_free) {
	TypeError("not a Gtk object");
    }
    Data_Get_Struct(data, GtkObject, gtkp);
    if (!GTK_IS_OBJECT(gtkp)) {
	TypeError("not a GtkObject");
    }

    return gtkp;
}

static GtkWidget*
get_widget(obj)
    VALUE obj;
{
    GtkObject *data = get_gobject(obj);

    return GTK_WIDGET(data);
}

static VALUE
get_value_from_gobject(obj)
    GtkObject *obj;
{
    return (VALUE)gtk_object_get_user_data(obj);
}

static void
clear_gobject(obj)
    VALUE obj;
{
    rb_ivar_set(obj, id_relatives, Qnil);
}

static void
add_relative(obj, relative)
    VALUE obj, relative;
{
    VALUE ary = rb_ivar_get(obj, id_relatives);

    if (TYPE(ary) != T_ARRAY) {
	ary = ary_new();
	rb_ivar_set(obj, id_relatives, ary);
    }
    ary_push(ary, relative);
}

static VALUE gtk_object_list;

static void
gobj_free(obj)
    GtkObject *obj;
{
    /* just for type mark */
}

static void
delete_gobject(gtkobj, obj)
    GtkObject *gtkobj;
    VALUE obj;
{
    struct RData *data;

    data = RDATA(rb_ivar_get(obj, id_gtkdata));
    data->dfree = 0;
    data->data = 0;
    ary_delete(gtk_object_list, obj);
}

static void
set_gobject(obj, gtkobj)
    VALUE obj;
    GtkObject *gtkobj;
{
    VALUE data;

    data = Data_Wrap_Struct(cData, 0, gobj_free, gtkobj);
    gtk_object_set_user_data(gtkobj, (gpointer)obj);

    rb_ivar_set(obj, id_gtkdata, data);
    gtk_signal_connect(gtkobj, "destroy",
		       (GtkSignalFunc)delete_gobject, (gpointer)obj);
    ary_push(gtk_object_list, obj);
}

static VALUE
make_gobject(klass, gtkobj)
    VALUE klass;
    GtkObject *gtkobj;
{
    VALUE obj = obj_alloc(klass);

    set_gobject(obj, gtkobj);
    rb_funcall(obj, id_init, 0, 0);
    return obj;
}

static void
set_widget(obj, widget)
    VALUE obj;
    GtkWidget *widget;
{
    set_gobject(obj, GTK_OBJECT(widget));
}

static VALUE
make_widget(klass, widget)
    VALUE klass;
    GtkWidget *widget;
{
    VALUE obj;

    return make_gobject(klass, GTK_OBJECT(widget));
}

static void
free_gstyle(style)
    GtkStyle *style;
{
    gtk_style_unref(style);
}

static VALUE
make_gstyle(style)
    GtkStyle *style;
{
    VALUE obj;

    gtk_style_ref(style);
    obj = Data_Wrap_Struct(gStyle, 0, free_gstyle, style);
    rb_funcall(obj, id_init, 0, 0);

    return obj;
}

static GtkStyle*
get_gstyle(style)
    VALUE style;
{
    GtkStyle *gstyle;

    if (NIL_P(style)) return NULL;
    if (!obj_is_instance_of(style, gStyle)) {
	TypeError("not a GtkStyle");
    }
    Data_Get_Struct(style, GtkStyle, gstyle);

    return gstyle;
}

static void
free_gaccel(tbl)
    GtkAcceleratorTable *tbl;
{
    gtk_accelerator_table_unref(tbl);
}

static VALUE
make_gtkacceltbl(tbl)
    GtkAcceleratorTable *tbl;
{
    VALUE obj;

    gtk_accelerator_table_ref(tbl);
    obj = Data_Wrap_Struct(gAcceleratorTable, 0, free_gaccel, tbl);
    rb_funcall(obj, id_init, 0, 0);

    return obj;
}

static GtkAcceleratorTable*
get_gtkacceltbl(value)
    VALUE value;
{
    GtkAcceleratorTable *tbl;

    if (NIL_P(value)) return NULL;

    if (!obj_is_instance_of(value, gAcceleratorTable)) {
	TypeError("not an AcceleratorTable");
    }
    Data_Get_Struct(value, GtkAcceleratorTable, tbl);

    return tbl;
}

static VALUE
make_gtkprevinfo(info)
    GtkPreviewInfo *info;
{
    VALUE obj = Data_Wrap_Struct(gAcceleratorTable, 0, 0, info);

    rb_funcall(obj, id_init, 0, 0);
    return obj;
}

static GtkPreviewInfo*
get_gtkprevinfo(value)
    VALUE value;
{
    GtkPreviewInfo *info;

    if (NIL_P(value)) return NULL;

    if (!obj_is_instance_of(value, gPreviewInfo)) {
	TypeError("not a PreviewInfo");
    }
    Data_Get_Struct(value, GtkPreviewInfo, info);

    return info;
}

static void
exec_callback(widget, data, nparams, params)
    GtkWidget *widget;
    VALUE data;
    int nparams;
    GtkType *params;
{
    VALUE self = get_value_from_gobject(GTK_OBJECT(widget));
    VALUE proc = RARRAY(data)->ptr[0];
    VALUE event = RARRAY(data)->ptr[1];
    ID id = NUM2INT(event);

    if (NIL_P(proc) && rb_respond_to(self, id)) {
	rb_funcall(self, id, 3, self,
		   INT2FIX(nparams), INT2NUM((INT)params));
    }
    else {
	rb_funcall(proc, id_call, 1, self);
    }
}

static void
free_ttips(tips)
    GtkTooltips *tips;
{
    gtk_tooltips_unref(tips);
}

static VALUE
make_ttips(klass, tips)
    VALUE klass;
    GtkTooltips *tips;
{
    VALUE obj;

    gtk_tooltips_ref(tips);
    obj = Data_Wrap_Struct(klass, 0, free_ttips, tips);
    rb_funcall(obj, id_init, 0, 0);
    return obj;
}

static GtkTooltips*
get_ttips(tips)
    VALUE tips;
{
    GtkTooltips *gtips;

    if (NIL_P(tips)) return NULL;

    if (!obj_is_instance_of(tips, gTooltips)) {
	TypeError("not a GtkTooltips");
    }
    Data_Get_Struct(tips, GtkTooltips, gtips);

    return gtips;
}

static void
free_gdkfont(font)
    GdkFont *font;
{
    gdk_font_unref(font);
}

static VALUE
make_gdkfont(font)
    GdkFont *font;
{
    VALUE obj;

    gdk_font_ref(font);
    obj = Data_Wrap_Struct(gdkFont, 0, free_gdkfont, font);
    rb_funcall(obj, id_init, 0, 0);
    return obj;
}

static GdkFont*
get_gdkfont(font)
    VALUE font;
{
    GdkFont *gfont;

    if (NIL_P(font)) return NULL;

    if (!obj_is_instance_of(font, gdkFont)) {
	TypeError("not a GdkFont");
    }
    Data_Get_Struct(font, GdkFont, gfont);

    return gfont;
}

static VALUE
gdkfnt_equal(fn1, fn2)
    VALUE fn1, fn2;
{
    if (gdk_font_equal(get_gdkfont(fn1), get_gdkfont(fn2)))
	return TRUE;
    return FALSE;
}

static void
free_tobj(obj)
    gpointer obj;
{
    free(obj);
}

static VALUE
make_tobj(obj, klass, size)
    gpointer obj;
    VALUE klass;
    int size;
{
    gpointer copy;
    VALUE data;

    copy = xmalloc(size);
    memcpy(copy, obj, size);
    data = Data_Wrap_Struct(klass, 0, free_tobj, copy);
    rb_funcall(data, id_init, 0, 0);

    return data;
}

static gpointer
get_tobj(obj, klass)
    VALUE obj, klass;
{
    void *ptr;

    if (NIL_P(obj)) return NULL;

    if (!obj_is_instance_of(obj, klass)) {
	TypeError("not a %s", rb_class2name(klass));
    }
    Data_Get_Struct(obj, void, ptr);

    return ptr;
}

#define make_gdkcolor(c) make_tobj(c, gdkColor, sizeof(GdkColor))
#define get_gdkcolor(c) ((GdkColor*)get_tobj(c, gdkColor))

#define make_gdkrect(c) make_tobj(c, gdkRectangle, sizeof(GdkRectangle))
#define get_gdkrect(c) ((GdkRectangle*)get_tobj(c, gdkRectangle))

#define make_gdksegment(c) make_tobj(c, gdkSegment, sizeof(GdkSegment))
#define get_gdksegment(c) ((GdkSegment*)get_tobj(c, gdkSegment))

#define make_gdkwinattr(c) make_tobj(c, gdkWindowAttr, sizeof(GdkWindowAttr))
#define get_gdkwinattr(c) ((GdkWindowAttr*)get_tobj(c, gdkWindowAttr))

#define make_gdkwinattr(c) make_tobj(c, gdkWindowAttr, sizeof(GdkWindowAttr))
#define get_gdkwinattr(c) ((GdkWindowAttr*)get_tobj(c, gdkWindowAttr))

#define make_gallocation(c) make_tobj(c, gAllocation, sizeof(GtkAllocation))
#define get_gallocation(c) ((GtkAllocation*)get_tobj(c, gAllocation))

#define make_grequisiton(c) make_tobj(c, gRequisiton, sizeof(GtkRequisition))
#define get_grequisiton(c) ((GtkRequisition*)get_tobj(c, gRequisiton))

#define make_gdkrectangle(r) make_tobj(r, gdkRectangle, sizeof(GdkRectangle))
#define get_gdkrectangle(r) ((GdkRectangle*)get_tobj(r, gdkRectangle))

static void
free_gdkcmap(cmap)
    GdkColormap *cmap;
{
    gdk_colormap_unref(cmap);
}

static VALUE
make_gdkcmap(cmap)
    GdkColormap *cmap;
{
    gdk_colormap_ref(cmap);
    return Data_Wrap_Struct(gdkColormap, 0, free_gdkcmap, cmap);
}

static GdkColormap*
get_gdkcmap(cmap)
    VALUE cmap;
{
    GdkColormap *gcmap;

    if (NIL_P(cmap)) return NULL;

    if (!obj_is_kind_of(cmap, gdkColormap)) {
	TypeError("not a GdkColormap");
    }
    Data_Get_Struct(cmap, GdkColormap, gcmap);

    return gcmap;
}

static VALUE
make_gdkvisual(visual)
    GdkVisual *visual;
{
    return Data_Wrap_Struct(gdkVisual, 0, 0, visual);
}

static GdkVisual*
get_gdkvisual(visual)
    VALUE visual;
{
    GdkVisual *gvisual;

    if (NIL_P(visual)) return NULL;

    if (!obj_is_kind_of(visual, gdkVisual)) {
	TypeError("not a GdkVisual");
    }
    Data_Get_Struct(visual, GdkVisual, gvisual);

    return gvisual;
}

static void
free_gdkwindow(window)
    GdkWindow *window;
{
    gdk_window_unref(window);
}

static VALUE
make_gdkwindow(window)
    GdkWindow *window;
{
    gdk_window_ref(window);
    return Data_Wrap_Struct(gdkWindow, 0, free_gdkwindow, window);
}

static GdkWindow*
get_gdkwindow(window)
    VALUE window;
{
    GdkWindow *gwindow;

    if (NIL_P(window)) return NULL;

    if (!obj_is_kind_of(window, gdkWindow)) {
	TypeError("not a GdkWindow");
    }
    Data_Get_Struct(window, GdkWindow, gwindow);

    return gwindow;
}

static void
free_gdkpixmap(pixmap)
    GdkPixmap *pixmap;
{
    gdk_pixmap_unref(pixmap);
}

static VALUE
make_gdkpixmap(klass, pixmap)
    VALUE klass;
    GdkPixmap *pixmap;
{
    gdk_pixmap_ref(pixmap);
    return Data_Wrap_Struct(klass, 0, free_gdkpixmap, pixmap);
}

static GdkPixmap*
get_gdkpixmap(pixmap)
    VALUE pixmap;
{
    GdkPixmap *gpixmap;

    if (NIL_P(pixmap)) return NULL;

    if (!obj_is_kind_of(pixmap, gdkPixmap)) {
	TypeError("not a GdkPixmap");
    }
    Data_Get_Struct(pixmap, GdkPixmap, gpixmap);

    return gpixmap;
}

static VALUE
gdkpmap_s_new(self, win, w, h, depth)
    VALUE self, win, w, h, depth;
{
    GdkPixmap *new;
    GdkWindow *window = get_gdkwindow(win);

    new = gdk_pixmap_new(window, NUM2INT(w), NUM2INT(h), NUM2INT(depth));
    return make_gdkpixmap(self, new);
}

static VALUE
gdkpmap_create_from_data(self, win, data, w, h, depth, fg, bg)
    VALUE self, win, data, w, h, depth, fg, bg;
{
    GdkPixmap *new;
    GdkWindow *window = get_gdkwindow(win);

    Check_Type(data, T_STRING);
    new = gdk_pixmap_create_from_data(window,
				      RSTRING(data)->ptr,
				      NUM2INT(w), NUM2INT(h),
				      NUM2INT(depth),
				      get_gdkcolor(fg),
				      get_gdkcolor(bg));
    return make_gdkpixmap(self, new);
}

static VALUE
gdkpmap_create_from_xpm(self, win, tcolor, fname)
    VALUE self, win, tcolor, fname;
{
    GdkPixmap *new;
    GdkBitmap *mask;
    GdkWindow *window = get_gdkwindow(win);

    Check_Type(fname, T_STRING);
    new = gdk_pixmap_create_from_xpm(window, &mask,
				     get_gdkcolor(tcolor),
				     RSTRING(fname)->ptr);
    if (!new) {
	ArgError("Pixmap not created from %s", RSTRING(fname)->ptr);
    }
    return assoc_new(make_gdkpixmap(self, new),
		     make_gdkpixmap(gdkBitmap, mask));
}

static VALUE
gdkpmap_create_from_xpm_d(self, win, tcolor, data)
    VALUE self, win, tcolor, data;
{
    GdkPixmap *new;
    GdkBitmap *mask;
    GdkWindow *window = get_gdkwindow(win);
    int i;
    gchar **buf;

    Check_Type(data, T_ARRAY);
    buf = ALLOCA_N(char*, RARRAY(data)->len);
    for (i=0; i<RARRAY(data)->len; i++) {
	Check_Type(RARRAY(data)->ptr[i], T_STRING);
	buf[i] = RSTRING(RARRAY(data)->ptr[i])->ptr;
    }

    new = gdk_pixmap_create_from_xpm_d(window, &mask,
				       get_gdkcolor(tcolor),
				       buf);

    return assoc_new(make_gdkpixmap(self, new),
		     make_gdkpixmap(gdkBitmap, mask));
}

static VALUE
gdkbmap_s_new(self, win, w, h)
    VALUE self, win, w, h;
{
    GdkPixmap *new;
    GdkWindow *window = get_gdkwindow(win);

    new = gdk_pixmap_new(window, NUM2INT(w), NUM2INT(h), 1);
    return make_gdkpixmap(self, new);
}

static VALUE
gdkbmap_create_from_data(self, win, data, w, h)
    VALUE self, win, data, w, h;
{
    GdkBitmap *new;
    GdkWindow *window = get_gdkwindow(win);

    Check_Type(data, T_STRING);
    new = gdk_bitmap_create_from_data(window,
				      RSTRING(data)->ptr,
				      NUM2INT(w), NUM2INT(h));
    return make_gdkpixmap(self, (GdkPixmap*)new);
}

static void
free_gdkimage(image)
    GdkImage *image;
{
    gdk_image_destroy(image);
}

static VALUE
make_gdkimage(image)
    GdkImage *image;
{
    return Data_Wrap_Struct(gdkImage, 0, free_gdkimage, image);
}

static GdkImage*
get_gdkimage(image)
    VALUE image;
{
    GdkImage *gimage;

    if (NIL_P(image)) return NULL;

    if (!obj_is_instance_of(image, gdkImage)) {
	TypeError("not a GdkImage");
    }
    Data_Get_Struct(image, GdkImage, gimage);

    return gimage;
}

static void
free_gdkevent(event)
    GdkEvent *event;
{
    gdk_event_free(event);
}

static VALUE
make_gdkevent(event)
    GdkEvent *event;
{
    event = gdk_event_copy(event);
    return Data_Wrap_Struct(gdkEvent, 0, free_gdkevent, event);
}

static GdkEvent*
get_gdkevent(event)
    VALUE event;
{
    GdkEvent *gevent;

    if (NIL_P(event)) return NULL;

    if (!obj_is_instance_of(event, gdkEvent)) {
	TypeError("not a GdkEvent");
    }
    Data_Get_Struct(event, GdkEvent, gevent);

    return gevent;
}

static VALUE
glist2ary(list)
    GList *list; 
{
    VALUE ary = ary_new();

    while (list) {
	ary_push(ary, get_value_from_gobject(GTK_OBJECT(list->data)));
	list = list->next;
    }

    return ary;
}

static GList*
ary2glist(ary)
    VALUE ary;
{
    int i;
    GList *glist = NULL;

    Check_Type(ary, T_ARRAY);
    for (i=0; i<RARRAY(ary)->len; i++) {
	glist = g_list_prepend(glist,get_widget(RARRAY(ary)->ptr[i]));
    }

    return g_list_reverse(glist);
}

static GSList*
ary2gslist(ary)
    VALUE ary;
{
    int i;
    GSList *glist = NULL;

    if (NIL_P(ary)) return NULL;
    Check_Type(ary, T_ARRAY);
    for (i=0; i<RARRAY(ary)->len; i++) {
	glist = g_slist_append(glist,get_widget(RARRAY(ary)->ptr[i]));
    }

    return glist;
}

static VALUE
gslist2ary(list)
    GSList *list; 
{
    VALUE ary = ary_new();

    while (list) {
	ary_push(ary, get_value_from_gobject(GTK_OBJECT(list->data)));
	list = list->next;
    }

    return ary;
}

static VALUE
gobj_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    Fail("can't instantiate class %s", rb_class2name(self));
}

static VALUE
gobj_smethod_added(self, id)
    VALUE self, id;
{
    GtkObject *obj = get_gobject(self);
    char *name = rb_id2name(NUM2INT(id));
    

    if (gtk_signal_lookup(name, GTK_OBJECT_TYPE(obj))) {
	VALUE handler = assoc_new(Qnil, id);

	add_relative(self, handler);
	gtk_signal_connect_interp(obj, name,
				  exec_callback, (gpointer)handler,
				  NULL, 0);
    }
    return Qnil;
}

static VALUE
gobj_destroy(self)
    VALUE self;
{
    printf("a\n");
    gtk_object_destroy(get_gobject(self));
    printf("b\n");
    clear_gobject(self);
    return Qnil;
}

static VALUE
gobj_set_flags(self, flags)
    VALUE self, flags;
{
    GtkObject *object = get_gobject(self);
    GTK_OBJECT_SET_FLAGS(object, NUM2INT(flags));
    return self;
}

static VALUE
gobj_unset_flags(self, flags)
    VALUE self, flags;
{
    GtkObject *object = get_gobject(self);
    GTK_OBJECT_UNSET_FLAGS(object, NUM2INT(flags));
    return self;
}

static VALUE
gobj_sig_connect(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE sig, handler;
    GtkWidget *widget = get_widget(self);
    ID id = 0;
    int n;

    rb_scan_args(argc, argv, "11", &sig, &handler);
    Check_Type(sig, T_STRING);
    if (NIL_P(handler) && iterator_p()) {
	handler = f_lambda();
	id = rb_intern(RSTRING(sig)->ptr);
    }
    handler = assoc_new(handler, INT2NUM(id));
    add_relative(self, handler);
    n = gtk_signal_connect_interp(GTK_OBJECT(widget), RSTRING(sig)->ptr,
				  exec_callback, (gpointer)handler,
				  NULL, 0);

    return INT2FIX(n);
}

static VALUE
gobj_sig_connect_after(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE sig, handler;
    GtkWidget *widget = get_widget(self);
    ID id = 0;
    int n;

    rb_scan_args(argc, argv, "11", &sig, &handler);
    Check_Type(sig, T_STRING);
    if (NIL_P(handler) && iterator_p()) {
	handler = f_lambda();
	id = rb_intern(RSTRING(sig)->ptr);
    }
    add_relative(self, handler);
    n = gtk_signal_connect_interp(GTK_OBJECT(widget), RSTRING(sig)->ptr,
				  exec_callback, (gpointer)handler,
				  NULL, 1);

    return INT2FIX(n);
}

static VALUE
cont_bwidth(self, width)
    VALUE self, width;
{
    GtkWidget *widget = get_widget(self);
    gtk_container_border_width(GTK_CONTAINER(widget), NUM2INT(width));
    return self;
}

static VALUE
cont_add(self, other)
    VALUE self, other;
{
    GtkWidget *widget = get_widget(self);

    gtk_container_add(GTK_CONTAINER(widget), get_widget(other));
    return self;
}

static VALUE
cont_disable_resize(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_container_disable_resize(GTK_CONTAINER(widget));
    return self;
}

static VALUE
cont_enable_resize(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_container_enable_resize(GTK_CONTAINER(widget));
    return self;
}

static VALUE
cont_block_resize(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_container_block_resize(GTK_CONTAINER(widget));
    return self;
}

static VALUE
cont_unblock_resize(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_container_unblock_resize(GTK_CONTAINER(widget));
    return self;
}

static VALUE
cont_need_resize(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_container_need_resize(GTK_CONTAINER(widget));
    return self;
}

static VALUE
cont_foreach(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE callback;
    GtkWidget *widget = get_widget(self);

    rb_scan_args(argc, argv, "01", &callback);
    if (NIL_P(callback)) {
	callback = f_lambda();
    }
    gtk_container_foreach(GTK_CONTAINER(widget), 
			  exec_callback, (gpointer)callback);
    return self;
}

static void
yield_callback(widget)
    GtkWidget *widget;
{
    rb_yield(get_value_from_gobject(GTK_OBJECT(widget)));
}

static VALUE
cont_each(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_container_foreach(GTK_CONTAINER(widget), 
			  yield_callback, 0);
    return self;
}

static VALUE
cont_focus(self, direction)
    VALUE self, direction;
{
    GtkWidget *widget = get_widget(self);

    gtk_container_focus(GTK_CONTAINER(widget),
			(GtkDirectionType)NUM2INT(direction));
    return self;
}

static void
cont_children_callback(widget, data)
    GtkWidget *widget;
    gpointer data;
{
    VALUE ary = (VALUE)data;

    ary_push(ary, get_value_from_gobject(GTK_OBJECT(widget)));
}

static VALUE
cont_children(self, direction)
    VALUE self, direction;
{
    GtkWidget *widget = get_widget(self);
    VALUE ary = ary_new();

    gtk_container_foreach(GTK_CONTAINER(widget),
			  cont_children_callback,
			  (gpointer)ary);
    return ary;
}

static VALUE
align_initialize(self, xalign, yalign, xscale, yscale)
    VALUE self, xalign, yalign, xscale, yscale;
{
    set_widget(self, gtk_alignment_new(NUM2DBL(xalign),
				       NUM2DBL(yalign),
				       NUM2DBL(xscale),
				       NUM2DBL(yscale)));
    return Qnil;
}

static VALUE
align_set(self, xalign, yalign, xscale, yscale)
    VALUE self, xalign, yalign, xscale, yscale;
{
    GtkWidget *widget = get_widget(self);

    gtk_alignment_set(GTK_ALIGNMENT(widget),
		      NUM2DBL(xalign), NUM2DBL(yalign),
		      NUM2DBL(xscale), NUM2DBL(yscale));
    return self;
}

static VALUE
misc_set_align(self, xalign, yalign)
    VALUE self, xalign, yalign;
{
    GtkWidget *widget = get_widget(self);

    gtk_misc_set_alignment(GTK_MISC(widget),
		      NUM2DBL(xalign), NUM2DBL(yalign));
    return self;
}

static VALUE
misc_set_padding(self, xpad, ypad)
    VALUE self, xpad, ypad;
{
    GtkWidget *widget = get_widget(self);

    gtk_misc_set_padding(GTK_MISC(widget),
			 NUM2DBL(xpad), NUM2DBL(ypad));
    return self;
}

static VALUE
arrow_initialize(self, arrow_t, shadow_t)
    VALUE self, arrow_t, shadow_t;
{
    set_widget(self, gtk_arrow_new((GtkArrowType)NUM2INT(arrow_t),
				   (GtkShadowType)NUM2INT(shadow_t)));
    return Qnil;
}

static VALUE
arrow_set(self, arrow_t, shadow_t)
    VALUE self, arrow_t, shadow_t;
{
    GtkWidget *widget = get_widget(self);

    gtk_arrow_set(GTK_ARROW(widget),
		  (GtkArrowType)NUM2INT(arrow_t),
		  (GtkShadowType)NUM2INT(shadow_t));
    return self;
}

static VALUE
frame_initialize(self, label)
    VALUE self, label;
{
    set_widget(self, gtk_frame_new(STR2CSTR(label)));
    return Qnil;
}

static VALUE
frame_set_label(self, label)
    VALUE self, label;
{
    GtkWidget *widget = get_widget(self);

    gtk_frame_set_label(GTK_FRAME(widget), STR2CSTR(label));
    return self;
}

static VALUE
frame_set_label_align(self, xalign, yalign)
    VALUE self, xalign, yalign;
{
    GtkWidget *widget = get_widget(self);

    gtk_frame_set_label_align(GTK_FRAME(widget),
			      NUM2DBL(xalign),
			      NUM2DBL(yalign));

    return self;
}

static VALUE
frame_set_shadow_type(self, type)
    VALUE self, type;
{
    GtkWidget *widget = get_widget(self);

    gtk_frame_set_shadow_type(GTK_FRAME(widget),
			      (GtkShadowType)NUM2INT(type));
    return self;
}

static VALUE
aframe_initialize(self, label, xalign, yalign, ratio, obey_child)
    VALUE self, label, xalign, yalign, ratio, obey_child;
{
    set_widget(self, gtk_aspect_frame_new(STR2CSTR(label),
					  NUM2DBL(xalign),
					  NUM2DBL(yalign),
					  NUM2DBL(ratio),
					  RTEST(obey_child)));
    return Qnil;
}

static VALUE
aframe_set(self, xalign, yalign, ratio, obey_child)
    VALUE self, xalign, yalign, ratio, obey_child;
{
    GtkWidget *widget = get_widget(self);

    gtk_aspect_frame_set(GTK_ASPECT_FRAME(widget),
			 NUM2DBL(xalign), NUM2DBL(yalign),
			 NUM2DBL(ratio), RTEST(obey_child));
    return self;
}

static VALUE
adj_initialize(self, value, lower, upper, step_inc, page_inc, page_size)
    VALUE self, value, lower, upper, step_inc, page_inc, page_size;
{
    set_widget(self, gtk_adjustment_new(NUM2DBL(value),
					NUM2DBL(lower),
					NUM2DBL(upper),
					NUM2DBL(step_inc),
					NUM2DBL(page_inc),
					NUM2DBL(page_size)));
    return Qnil;
}

static VALUE
widget_destroy(self)
    VALUE self;
{
    gtk_widget_destroy(get_widget(self));
    clear_gobject(self);

    return Qnil;
}

static VALUE
widget_show(self)
    VALUE self;
{
    gtk_widget_show(get_widget(self));
    return self;
}

static VALUE
widget_show_all(self)
    VALUE self;
{
    gtk_widget_show_all(get_widget(self));
    return self;
}

static VALUE
widget_hide(self)
    VALUE self;
{
    gtk_widget_hide(get_widget(self));
    return self;
}

static VALUE
widget_hide_all(self)
    VALUE self;
{
    gtk_widget_hide_all(get_widget(self));
    return self;
}

static VALUE
widget_map(self)
    VALUE self;
{
    gtk_widget_map(get_widget(self));
    return self;
}

static VALUE
widget_unmap(self)
    VALUE self;
{
    gtk_widget_unmap(get_widget(self));
    return self;
}

static VALUE
widget_realize(self)
    VALUE self;
{
    gtk_widget_realize(get_widget(self));
    return self;
}

static VALUE
widget_unrealize(self)
    VALUE self;
{
    gtk_widget_unrealize(get_widget(self));
    return self;
}

static VALUE
widget_queue_draw(self)
    VALUE self;
{
    gtk_widget_queue_draw(get_widget(self));
    return self;
}

static VALUE
widget_queue_resize(self)
    VALUE self;
{
    gtk_widget_queue_resize(get_widget(self));
    return self;
}

static VALUE
widget_draw(self, rect)
    VALUE self, rect;
{
    gtk_widget_draw(get_widget(self), get_gdkrectangle(rect));
    return self;
}

static VALUE
widget_draw_focus(self)
    VALUE self;
{
    gtk_widget_draw_focus(get_widget(self));
    return self;
}

static VALUE
widget_draw_default(self)
    VALUE self;
{
    gtk_widget_draw_default(get_widget(self));
    return self;
}

static VALUE
widget_draw_children(self)
    VALUE self;
{
    gtk_widget_draw_children(get_widget(self));
    return self;
}

static VALUE
widget_size_request(self, req)
    VALUE self, req;
{
    gtk_widget_size_request(get_widget(self), get_grequisiton(req));
    return self;
}

static VALUE
widget_size_allocate(self, alloc)
    VALUE self, alloc;
{
    gtk_widget_size_allocate(get_widget(self), get_gallocation(alloc));
    return self;
}

static VALUE
widget_inst_accel(self, accel, sig, key, mod)
    VALUE self, accel, sig, key, mod;
{
    gtk_widget_install_accelerator(get_widget(self),
				   get_gtkacceltbl(accel),
				   STR2CSTR(sig),
				   NUM2INT(key),
				   (guint8)NUM2INT(mod));
    return self;
}

static VALUE
widget_rm_accel(self, accel, sig)
    VALUE self, accel, sig;
{
    gtk_widget_remove_accelerator(get_widget(self),
				  get_gtkacceltbl(accel),
				  STR2CSTR(sig));
    return self;
}

static VALUE
widget_event(self, event)
    VALUE self, event;
{
    int n = gtk_widget_event(get_widget(self), get_gdkevent(event));
    return NUM2INT(n);
}

static VALUE
widget_activate(self)
    VALUE self;
{
    gtk_widget_activate(get_widget(self));
    return self;
}

static VALUE
widget_grab_focus(self)
    VALUE self;
{
    gtk_widget_grab_focus(get_widget(self));
    return self;
}

static VALUE
widget_grab_default(self)
    VALUE self;
{
    gtk_widget_grab_default(get_widget(self));
    return self;
}

static VALUE
widget_restore_state(self)
    VALUE self;
{
    gtk_widget_restore_state(get_widget(self));
    return self;
}

static VALUE
widget_visible(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    
    if (GTK_WIDGET_VISIBLE(widget))
	return TRUE;
    return FALSE;
}

static VALUE
widget_reparent(self, parent)
    VALUE self, parent;
{
    gtk_widget_reparent(get_widget(self), get_widget(parent));
    return self;
}

static VALUE
widget_popup(self, x, y)
    VALUE self, x, y;
{
    gtk_widget_popup(get_widget(self), NUM2INT(x), NUM2INT(y));
    return self;
}

static VALUE
widget_intersect(self, area, intersect)
    VALUE self, area, intersect;
{
    int n = gtk_widget_intersect(get_widget(self),
				 get_gdkrectangle(area),
				 get_gdkrectangle(intersect));
    return NUM2INT(n);
}

static VALUE
widget_basic(self)
    VALUE self;
{
    int n = gtk_widget_basic(get_widget(self));
    return NUM2INT(n);
}

static VALUE
widget_set_state(self, state)
    VALUE self, state;
{
    gtk_widget_set_state(get_widget(self), (GtkStateType)NUM2INT(state));
    return self;
}

static VALUE
widget_set_style(self, style)
    VALUE self, style;
{
    gtk_widget_set_style(get_widget(self),
			 get_gstyle(style));
    return self;
}

static VALUE
widget_set_parent(self, parent)
    VALUE self, parent;
{
    gtk_widget_set_parent(get_widget(self), get_widget(parent));
    return self;
}

static VALUE
widget_set_name(self, name)
    VALUE self, name;
{
    gtk_widget_set_name(get_widget(self), STR2CSTR(name));
    return self;
}

static VALUE
widget_get_name(self)
    VALUE self;
{
    char *name = gtk_widget_get_name(get_widget(self));
    
    return str_new2(name);
}

static VALUE
widget_set_sensitive(self, sensitive)
    VALUE self, sensitive;
{
    gtk_widget_set_sensitive(get_widget(self), RTEST(sensitive));
    return self;
}

static VALUE
widget_set_uposition(self, x, y)
    VALUE self, x, y;
{
    gtk_widget_set_uposition(get_widget(self), NUM2INT(x), NUM2INT(y));
    return self;
}

static VALUE
widget_set_usize(self, w, h)
    VALUE self, w, h;
{
    gtk_widget_set_usize(get_widget(self), NUM2INT(w), NUM2INT(h));
    return self;
}

static VALUE
widget_set_events(self, events)
    VALUE self, events;
{
    gtk_widget_set_events(get_widget(self), NUM2INT(events));
    return self;
}

static VALUE
widget_set_eevents(self, mode)
    VALUE self, mode;
{
    gtk_widget_set_extension_events(get_widget(self),
				    (GdkExtensionMode)NUM2INT(mode));
    return self;
}

static VALUE
widget_unparent(self)
    VALUE self;
{
    gtk_widget_unparent(get_widget(self));
    return self;
}

static VALUE
widget_window(self)
    VALUE self;
{
    return make_gdkwindow(get_widget(self)->window);
}

static VALUE
widget_get_toplevel(self)
    VALUE self;
{
    return get_value_from_gobject(gtk_widget_get_toplevel(get_widget(self)));
}

static VALUE
widget_get_ancestor(self, type)
    VALUE self, type;
{
    GtkWidget *widget = get_widget(self);
#if 0
    if (obj_is_kind_of(type, cClass)) {
    }
#endif
    widget = gtk_widget_get_ancestor(widget, NUM2INT(type));

    return get_value_from_gobject(widget);
}

static VALUE
widget_get_colormap(self)
    VALUE self;
{
    GdkColormap *cmap = gtk_widget_get_colormap(get_widget(self));

    return make_gdkcmap(cmap);
}

static VALUE
widget_get_visual(self)
    VALUE self;
{
    GdkVisual *v = gtk_widget_get_visual(get_widget(self));

    return make_gdkvisual(v);
}

static VALUE
widget_get_style(self)
    VALUE self;
{
    GtkStyle *s = gtk_widget_get_style(get_widget(self));

    return make_gstyle(s);
}

static VALUE
widget_get_pointer(self)
    VALUE self;
{
    int x, y;

    gtk_widget_get_pointer(get_widget(self), &x, &y);
    return assoc_new(INT2FIX(x), INT2FIX(y));
}

static VALUE
widget_is_ancestor(self, ancestor)
    VALUE self, ancestor;
{
    if (gtk_widget_is_ancestor(get_widget(self), get_widget(ancestor))) {
	return TRUE;
    }
    return FALSE;
}

static VALUE
widget_is_child(self, child)
    VALUE self, child;
{
    if (gtk_widget_is_child(get_widget(self), get_widget(child))) {
	return TRUE;
    }
    return FALSE;
}

static VALUE
widget_get_events(self)
    VALUE self;
{
    int n = gtk_widget_get_events(get_widget(self));
    return NUM2INT(n);
}

static VALUE
widget_get_eevents(self)
    VALUE self;
{
    GdkExtensionMode m;
    m = gtk_widget_get_extension_events(get_widget(self));
    return NUM2INT((int)m);
}

static VALUE
widget_push_cmap(self, cmap)
    VALUE self, cmap;
{
    gtk_widget_push_colormap(get_gdkcmap(cmap));
    return Qnil;
}

static VALUE
widget_push_visual(self, visual)
    VALUE self, visual;
{
    gtk_widget_push_visual(get_gdkvisual(visual));
    return make_gdkcmap(visual);
}

static VALUE
widget_push_style(self, style)
    VALUE self, style;
{
    gtk_widget_push_style(get_gstyle(style));
    return Qnil;
}

static VALUE
widget_pop_cmap(self, cmap)
    VALUE self, cmap;
{
    gtk_widget_pop_colormap();
    return Qnil;
}

static VALUE
widget_pop_visual(self, visual)
    VALUE self, visual;
{
    gtk_widget_pop_visual();
    return Qnil;
}

static VALUE
widget_pop_style(self, style)
    VALUE self, style;
{
    gtk_widget_pop_style();
    return Qnil;
}

static VALUE
widget_set_default_cmap(self, cmap)
    VALUE self, cmap;
{
    gtk_widget_set_default_colormap(get_gdkcmap(cmap));
    return Qnil;
}

static VALUE
widget_set_default_visual(self, visual)
    VALUE self, visual;
{
    gtk_widget_set_default_visual(get_gdkvisual(visual));
    return make_gdkcmap(visual);
}

static VALUE
widget_set_default_style(self, style)
    VALUE self, style;
{
    gtk_widget_set_default_style(get_gstyle(style));
    return Qnil;
}

static VALUE
widget_get_default_cmap(self)
    VALUE self;
{
    GdkColormap *cmap = gtk_widget_get_default_colormap();

    return make_gdkcmap(cmap);
}

static VALUE
widget_get_default_visual(self)
    VALUE self;
{
    GdkVisual *v = gtk_widget_get_default_visual();

    return make_gdkvisual(v);
}

static VALUE
widget_get_default_style(self)
    VALUE self;
{
    GtkStyle *s = gtk_widget_get_default_style();

    return make_gstyle(s);
}

static VALUE
widget_propagate_default_style(self)
    VALUE self;
{
    gtk_widget_propagate_default_style();
    return Qnil;
}

static VALUE
bbox_get_child_size_default(self)
    VALUE self;
{
    int min_width, max_width;

    gtk_button_box_get_child_size_default(&min_width, &max_width);

    return assoc_new(INT2FIX(min_width), INT2FIX(max_width));
}

static VALUE
bbox_get_child_ipadding_default(self)
    VALUE self;
{
    int ipad_x, ipad_y;

    gtk_button_box_get_child_ipadding_default(&ipad_x, &ipad_y);
    return assoc_new(INT2FIX(ipad_x), INT2FIX(ipad_y));
}

static VALUE
bbox_set_child_size_default(self, min_width, max_width)
    VALUE self, min_width, max_width;
{
    gtk_button_box_set_child_size_default(NUM2INT(min_width),
					  NUM2INT(max_width));
    return Qnil;
}

static VALUE
bbox_set_child_ipadding_default(self, ipad_x, ipad_y)
    VALUE self, ipad_x, ipad_y;
{
    gtk_button_box_set_child_ipadding_default(NUM2INT(ipad_x),
					      NUM2INT(ipad_y));
    return Qnil;
}

static VALUE
bbox_get_spacing(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    int n = gtk_button_box_get_spacing(GTK_BUTTON_BOX(widget));

    return INT2FIX(n);
}

static VALUE
bbox_get_layout(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    int n = gtk_button_box_get_layout(GTK_BUTTON_BOX(widget));

    return INT2FIX(n);
}

static VALUE
bbox_get_child_size(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    int min_width, max_width;

    gtk_button_box_get_child_size(GTK_BUTTON_BOX(widget),
				  &min_width, &max_width);
    return assoc_new(INT2FIX(min_width), INT2FIX(max_width));
}

static VALUE
bbox_get_child_ipadding(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    int ipad_x, ipad_y;

    gtk_button_box_get_child_ipadding(GTK_BUTTON_BOX(widget),
				      &ipad_x, &ipad_y);
    return assoc_new(INT2FIX(ipad_x), INT2FIX(ipad_y));
}

static VALUE
bbox_set_spacing(self, spacing)
    VALUE self, spacing;
{
    GtkWidget *widget = get_widget(self);

    gtk_button_box_set_spacing(GTK_BUTTON_BOX(widget),
			       NUM2INT(spacing));
    return self;
}

static VALUE
bbox_set_layout(self, layout)
    VALUE self, layout;
{
    GtkWidget *widget = get_widget(self);

    gtk_button_box_set_layout(GTK_BUTTON_BOX(widget),
			      NUM2INT(layout));
    return self;
}

static VALUE
bbox_set_child_size(self, min_width, max_width)
    VALUE self, min_width, max_width;
{
    GtkWidget *widget = get_widget(self);

    gtk_button_box_set_child_size(GTK_BUTTON_BOX(widget),
				  NUM2INT(min_width),
				  NUM2INT(max_width));
    return self;
}

static VALUE
bbox_set_child_ipadding(self, ipad_x, ipad_y)
    VALUE self, ipad_x, ipad_y;
{
    GtkWidget *widget = get_widget(self);

    gtk_button_box_set_child_ipadding(GTK_BUTTON_BOX(widget),
				      NUM2INT(ipad_x),
				      NUM2INT(ipad_y));
    return self;
}

static VALUE
clist_initialize(self, titles)
    VALUE self, titles;
{
    GtkWidget *widget;

    if (TYPE(titles) == T_ARRAY) {
	char **buf;
	int i, len;

	Check_Type(titles, T_ARRAY);
	len = RARRAY(titles)->len;
	buf = ALLOCA_N(char*, len);
	for (i=0; i<len; i++) {
	    Check_Type(RARRAY(titles)->ptr[i], T_STRING);
	    buf[i] = RSTRING(RARRAY(titles)->ptr[i])->ptr;
	}
	widget = gtk_clist_new_with_titles(len, buf);
    }
    else {
	widget = gtk_clist_new(NUM2INT(titles));
    }
    set_widget(self, widget);

    return Qnil;
}

static VALUE
clist_set_border(self, border)
    VALUE self, border;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_border(GTK_CLIST(widget), (GtkShadowType)NUM2INT(border));
    return self;
}

static VALUE
clist_set_sel_mode(self, mode)
    VALUE self, mode;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_selection_mode(GTK_CLIST(widget),
				 (GtkSelectionMode)NUM2INT(mode));
    return self;
}

static VALUE
clist_set_policy(self, vpolicy, hpolicy)
    VALUE self, vpolicy, hpolicy;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_policy(GTK_CLIST(widget),
			 (GtkPolicyType)NUM2INT(vpolicy),
			 (GtkPolicyType)NUM2INT(hpolicy));
    return self;
}

static VALUE
clist_freeze(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_freeze(GTK_CLIST(widget));
    return self;
}

static VALUE
clist_thaw(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_thaw(GTK_CLIST(widget));
    return self;
}

static VALUE
clist_col_titles_show(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_column_titles_show(GTK_CLIST(widget));
    return self;
}

static VALUE
clist_col_titles_hide(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_column_titles_hide(GTK_CLIST(widget));
    return self;
}

static VALUE
clist_col_title_active(self, column)
    VALUE self, column;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_column_title_active(GTK_CLIST(widget), NUM2INT(column));
    return self;
}

static VALUE
clist_col_title_passive(self, column)
    VALUE self, column;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_column_title_passive(GTK_CLIST(widget), NUM2INT(column));
    return self;
}

static VALUE
clist_col_titles_active(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_column_titles_active(GTK_CLIST(widget));
    return self;
}

static VALUE
clist_col_titles_passive(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_column_titles_passive(GTK_CLIST(widget));
    return self;
}

static VALUE
clist_set_col_title(self, col, title)
    VALUE self, col, title;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_column_title(GTK_CLIST(widget),
			       NUM2INT(col),
			       STR2CSTR(title));
    return self;
}

static VALUE
clist_set_col_wigdet(self, col, win)
    VALUE self, col, win;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_column_widget(GTK_CLIST(widget),
				NUM2INT(col),
				get_widget(win));
    return self;
}

static VALUE
clist_set_col_just(self, col, just)
    VALUE self, col, just;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_column_justification(GTK_CLIST(widget),
				       NUM2INT(col),
				       (GtkJustification)NUM2INT(just));
    return self;
}

static VALUE
clist_set_col_width(self, col, width)
    VALUE self, col, width;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_column_width(GTK_CLIST(widget),
			       NUM2INT(col), NUM2INT(width));
    return self;
}

static VALUE
clist_set_row_height(self, height)
    VALUE self, height;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_row_height(GTK_CLIST(widget), NUM2INT(height));
    return self;
}

static VALUE
clist_moveto(self, row, col, row_align, col_align)
    VALUE self, row, col, row_align, col_align;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_moveto(GTK_CLIST(widget),
		     NUM2INT(row), NUM2INT(col),
		     NUM2INT(row_align), NUM2INT(col_align));
    return self;
}

static VALUE
clist_set_text(self, row, col, text)
    VALUE self, row, col, text;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_text(GTK_CLIST(widget),
		       NUM2INT(row), NUM2INT(col),
		       STR2CSTR(text));
    return self;
}

static VALUE
clist_set_pixmap(self, row, col, pixmap, mask)
    VALUE self, row, col, pixmap, mask;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_pixmap(GTK_CLIST(widget),
			 NUM2INT(row), NUM2INT(col),
			 get_gdkpixmap(pixmap),
			 (GdkBitmap*)get_gdkpixmap(mask));
    return self;
}

static VALUE
clist_set_pixtext(self, row, col, text, spacing, pixmap, mask)
    VALUE self, row, col, text, spacing, pixmap, mask;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_pixtext(GTK_CLIST(widget),
			  NUM2INT(row), NUM2INT(col),
			  STR2CSTR(text),
			  NUM2INT(spacing),
			  get_gdkpixmap(pixmap),
			 (GdkBitmap*)get_gdkpixmap(mask));
    return self;
}

static VALUE
clist_set_foreground(self, row, color)
    VALUE self, row, color;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_foreground(GTK_CLIST(widget),
			     NUM2INT(row), get_gdkcolor(color));
    return self;
}

static VALUE
clist_set_background(self, row, color)
    VALUE self, row, color;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_background(GTK_CLIST(widget),
			     NUM2INT(row), get_gdkcolor(color));
    return self;
}

static VALUE
clist_set_shift(self, row, col, verticle, horizontal)
    VALUE self, row, col, verticle, horizontal;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_set_shift(GTK_CLIST(widget),
			NUM2INT(row), NUM2INT(col),
			NUM2INT(verticle), NUM2INT(horizontal));
    return self;
}

static VALUE
clist_append(self, text)
    VALUE self, text;
{
    GtkWidget *widget = get_widget(self);
    char **buf;
    int i, len;

    Check_Type(text, T_ARRAY);
    len = GTK_CLIST(widget)->columns;
    if (len > RARRAY(text)->len) {
	ArgError("text too short");
    }
    buf = ALLOCA_N(char*, len);
    for (i=0; i<len; i++) {
	Check_Type(RARRAY(text)->ptr[i], T_STRING);
	buf[i] = RSTRING(RARRAY(text)->ptr[i])->ptr;
    }
    i = gtk_clist_append(GTK_CLIST(widget), buf);
    return INT2FIX(i);
}

static VALUE
clist_insert(self, row, text)
    VALUE self, row, text;
{
    GtkWidget *widget = get_widget(self);
    char **buf;
    int i, len;

    Check_Type(text, T_ARRAY);
    len = GTK_CLIST(widget)->columns;
    if (len > RARRAY(text)->len) {
	ArgError("text too short");
    }
    buf = ALLOCA_N(char*, len);
    for (i=0; i<len; i++) {
	Check_Type(RARRAY(text)->ptr[i], T_STRING);
	buf[i] = RSTRING(RARRAY(text)->ptr[i])->ptr;
    }
    gtk_clist_insert(GTK_CLIST(widget), NUM2INT(row), buf);
    return self;
}

static VALUE
clist_remove(self, row)
    VALUE self, row;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_remove(GTK_CLIST(widget), NUM2INT(row));
    return self;
}

static VALUE
clist_set_row_data(self, row, data)
    VALUE self, row, data;
{
    GtkWidget *widget = get_widget(self);

    add_relative(self, data);
    gtk_clist_set_row_data(GTK_CLIST(widget), NUM2INT(row), (gpointer)data);
    return self;
}

static VALUE
clist_get_row_data(self, row)
    VALUE self, row;
{
    GtkWidget *widget = get_widget(self);

    return (VALUE)gtk_clist_get_row_data(GTK_CLIST(widget), NUM2INT(row));
}

static VALUE
clist_select_row(self, row, col)
    VALUE self, row, col;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_select_row(GTK_CLIST(widget), NUM2INT(row), NUM2INT(col));
    return self;
}

static VALUE
clist_unselect_row(self, row, col)
    VALUE self, row, col;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_unselect_row(GTK_CLIST(widget), NUM2INT(row), NUM2INT(col));
    return self;
}

static VALUE
clist_clear(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_clist_clear(GTK_CLIST(widget));
    return self;
}

static VALUE
gwin_initialize(self, type)
    VALUE self, type;
{
    set_widget(self, gtk_window_new(NUM2INT(type)));
    return Qnil;
}

static VALUE
gwin_set_policy(self, shrink, grow, auto_shrink)
    VALUE self, shrink, grow, auto_shrink;
{
    GtkWidget *widget = get_widget(self);

    gtk_window_set_policy(GTK_WINDOW(widget),
			  RTEST(shrink), RTEST(grow), RTEST(auto_shrink));
    return self;
}

static VALUE
gwin_set_title(self, title)
    VALUE self, title;
{
    GtkWidget *widget = get_widget(self);

    gtk_window_set_title(GTK_WINDOW(widget), STR2CSTR(title));
    return self;
}

static VALUE
gwin_position(self, pos)
    VALUE self, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_window_position(GTK_WINDOW(widget),
			(GtkWindowPosition)NUM2INT(pos));

    return self;
}

static VALUE
gwin_set_wmclass(self, wmclass1, wmclass2)
    VALUE self, wmclass1, wmclass2;
{
    GtkWidget *widget = get_widget(self);

    gtk_window_set_wmclass(GTK_WINDOW(widget),
			   STR2CSTR(wmclass1),
			   STR2CSTR(wmclass2));
    return self;
}

static VALUE
gwin_set_focus(self, win)
    VALUE self, win;
{
    GtkWidget *widget = get_widget(self);

    gtk_window_set_focus(GTK_WINDOW(widget), get_widget(win));
    return self;
}

static VALUE
gwin_set_default(self, win)
    VALUE self, win;
{
    GtkWidget *widget = get_widget(self);

    gtk_window_set_default(GTK_WINDOW(widget), get_widget(win));
    return self;
}

static VALUE
gwin_add_accel(self, accel)
    VALUE self, accel;
{
    GtkWidget *widget = get_widget(self);

    gtk_window_add_accelerator_table(GTK_WINDOW(widget),
				     get_gtkacceltbl(accel));
    return self;
}

static VALUE
gwin_rm_accel(self, accel)
    VALUE self, accel;
{
    GtkWidget *widget = get_widget(self);

    gtk_window_remove_accelerator_table(GTK_WINDOW(widget),
					get_gtkacceltbl(accel));
    return self;
}

static VALUE
dialog_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_dialog_new());
    return Qnil;
}

static VALUE
fsel_initialize(self, title)
    VALUE self, title;
{
    set_widget(self, gtk_file_selection_new(STR2CSTR(title)));
    return Qnil;
}

static VALUE
fsel_set_fname(self, fname)
    VALUE self, fname;
{
    GtkWidget *widget = get_widget(self);
    
    Check_Type(fname, T_STRING);
    gtk_file_selection_set_filename(GTK_FILE_SELECTION(widget),
				    RSTRING(fname)->ptr);

    return self;
}

static VALUE
fsel_get_fname(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    gchar *fname;

    fname = gtk_file_selection_get_filename(GTK_FILE_SELECTION(widget));

    return str_new2(fname);
}

static VALUE
fsel_ok_button(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    VALUE b = rb_iv_get(self, "ok_button");

    if (NIL_P(b)) {
	GtkWidget *w = GTK_FILE_SELECTION(widget)->ok_button;
	b = make_widget(gButton, w);
	rb_iv_set(self, "ok_button", b);
    }

    return b;
}

static VALUE
fsel_cancel_button(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    VALUE b = rb_iv_get(self, "cancel_button");

    if (NIL_P(b)) {
	GtkWidget *w = GTK_FILE_SELECTION(widget)->cancel_button;
	b = make_widget(gButton, w);
	rb_iv_set(self, "cancel_button", b);
    }

    return b;
}

static VALUE
fsel_help_button(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    VALUE b = rb_iv_get(self, "help_button");

    if (NIL_P(b)) {
	GtkWidget *w = GTK_FILE_SELECTION(widget)->help_button;
	b = make_widget(gButton, w);
	rb_iv_set(self, "help_button", b);
    }

    return b;
}

static VALUE
label_initialize(self, label)
    VALUE self, label;
{
    set_widget(self, gtk_label_new(STR2CSTR(label)));
    return Qnil;
}

static VALUE
list_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_list_new());
    return Qnil;
}

static VALUE
list_set_sel_mode(self, mode)
    VALUE self, mode;
{
    GtkWidget *widget = get_widget(self);

    gtk_list_set_selection_mode(GTK_LIST(widget),
				(GtkSelectionMode)NUM2INT(mode));
    return self;
}

static VALUE
list_sel_mode(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    return INT2FIX(GTK_LIST(widget)->selection_mode);
}

static VALUE
list_selection(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    return glist2ary(GTK_LIST(widget)->selection);
}

static VALUE
list_insert_items(self, items, pos)
    VALUE self, items, pos;
{
    GtkWidget *widget = get_widget(self);
    GList *glist;

    glist = ary2glist(items);

    gtk_list_insert_items(GTK_LIST(widget), glist, NUM2INT(pos));
    g_list_free(glist);

    return self;
}

static VALUE
list_append_items(self, items)
    VALUE self, items;
{
    GtkWidget *widget = get_widget(self);
    GList *glist;

    glist = ary2glist(items);

    gtk_list_append_items(GTK_LIST(widget), glist);
    g_list_free(glist);

    return self;
}

static VALUE
list_prepend_items(self, items)
    VALUE self, items;
{
    GtkWidget *widget = get_widget(self);
    GList *glist;

    glist = ary2glist(items);
    gtk_list_prepend_items(GTK_LIST(widget), glist);
    g_list_free(glist);

    return self;
}

static VALUE
list_remove_items(self, items)
    VALUE self, items;
{
    GtkWidget *widget = get_widget(self);
    GList *glist;

    glist = ary2glist(items);
    gtk_list_remove_items(GTK_LIST(widget), glist);
    g_list_free(glist);

    return self;
}

static VALUE
list_clear_items(self, start, end)
    VALUE self, start, end;
{
    GtkWidget *widget = get_widget(self);

    gtk_list_clear_items(GTK_LIST(widget), NUM2INT(start), NUM2INT(end));
    return self;
}

static VALUE
list_select_item(self, pos)
    VALUE self, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_list_select_item(GTK_LIST(widget), NUM2INT(pos));
    return self;
}

static VALUE
list_unselect_item(self, pos)
    VALUE self, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_list_unselect_item(GTK_LIST(widget), NUM2INT(pos));
    return self;
}

static VALUE
list_select_child(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    gtk_list_select_child(GTK_LIST(widget), get_widget(child));
    return self;
}

static VALUE
list_unselect_child(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    gtk_list_unselect_child(GTK_LIST(widget), get_widget(child));
    return self;
}

static VALUE
list_child_position(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);
    gint pos;

    pos = gtk_list_child_position(GTK_LIST(widget), get_widget(child));
    return INT2FIX(pos);
}

static VALUE
item_select(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_item_select(GTK_ITEM(widget));
    return self;
}

static VALUE
item_deselect(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_item_deselect(GTK_ITEM(widget));
    return self;
}

static VALUE
item_toggle(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_item_toggle(GTK_ITEM(widget));
    return self;
}

static VALUE
litem_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE label;
    GtkWidget *widget;

    if (rb_scan_args(argc, argv, "01", &label) == 1) {
	widget = gtk_list_item_new_with_label(STR2CSTR(label));
    }
    else {
	widget = gtk_list_item_new();
    }

    set_widget(self, widget);
    return Qnil;
}

static VALUE
mshell_append(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_shell_append(GTK_MENU_SHELL(widget), get_widget(child));
    return self;
}

static VALUE
mshell_prepend(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_shell_prepend(GTK_MENU_SHELL(widget), get_widget(child));
    return self;
}

static VALUE
mshell_insert(self, child, pos)
    VALUE self, child, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_shell_insert(GTK_MENU_SHELL(widget), get_widget(child),
			  NUM2INT(pos));
    return self;
}

static VALUE
mshell_deactivate(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_shell_deactivate(GTK_MENU_SHELL(widget));
    return self;
}

static VALUE
menu_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_menu_new());
    return Qnil;
}

static VALUE
menu_append(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_append(GTK_MENU(widget), get_widget(child));
    return self;
}

static VALUE
menu_prepend(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_prepend(GTK_MENU(widget), get_widget(child));
    return self;
}

static VALUE
menu_insert(self, child, pos)
    VALUE self, child, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_insert(GTK_MENU(widget), get_widget(child), NUM2INT(pos));
    return self;
}

static void
menu_pos_func(menu, x, y, data)
    GtkMenu *menu;
    gint x, y;
    gpointer data;
{
    VALUE m = get_value_from_gobject(GTK_OBJECT(menu));

    rb_funcall((VALUE)data, 3, m, INT2FIX(x), INT2FIX(y));
}

static VALUE
menu_popup(self, pshell, pitem, func, button, activate_time)
    VALUE self, pshell, pitem, func, button, activate_time;
{
    GtkWidget *widget = get_widget(self);
    GtkMenuPositionFunc pfunc = NULL;
    gpointer data = NULL;

    if (!NIL_P(func)) {
	pfunc = menu_pos_func;
	data = (gpointer)func;
	add_relative(self, func);
    }
    gtk_menu_popup(GTK_MENU(widget),
		   get_widget(pshell), get_widget(pitem),
		   pfunc,
		   data,
		   NUM2INT(button),
		   NUM2INT(activate_time));
    return self;
}

static VALUE
menu_popdown(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_popdown(GTK_MENU(widget));
    return self;
}

static VALUE
menu_get_active(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    GtkWidget *mitem = gtk_menu_get_active(GTK_MENU(widget));

    set_widget(gMenuItem, mitem);
    return Qnil;
}

static VALUE
menu_set_active(self, active)
    VALUE self, active;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_set_active(GTK_MENU(widget), NUM2INT(active));
    return self;
}

static VALUE
menu_set_acceltbl(self, table)
    VALUE self, table;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_set_accelerator_table(GTK_MENU(widget),
				   get_gtkacceltbl(table));
    return self;
}

static VALUE
mbar_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_menu_bar_new());
    return Qnil;
}

static VALUE
mbar_append(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_bar_append(GTK_MENU_BAR(widget), get_widget(child));
    return self;
}

static VALUE
mbar_prepend(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_bar_prepend(GTK_MENU_BAR(widget), get_widget(child));
    return self;
}
static VALUE
mbar_insert(self, child, pos)
    VALUE self, child, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_bar_insert(GTK_MENU_BAR(widget),
			get_widget(child), NUM2INT(pos));
    return self;
}

static VALUE
mitem_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
{
    VALUE label;
    GtkWidget *widget;

    if (rb_scan_args(argc, argv, "01", &label) == 1) {
	widget = gtk_menu_item_new_with_label(STR2CSTR(label));
    }
    else {
	widget = gtk_menu_item_new();
    }

    set_widget(self, widget);
    return Qnil;
}

static VALUE
mitem_set_submenu(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_item_set_submenu(GTK_MENU_ITEM(widget), get_widget(child));
    return self;
}

static VALUE
mitem_set_placement(self, place)
    VALUE self, place;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_item_set_placement(GTK_MENU_ITEM(widget), 
				(GtkSubmenuPlacement)NUM2INT(place));
    return self;
}

static VALUE
mitem_accelerator_size(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_item_accelerator_size(GTK_MENU_ITEM(widget));
    return self;
}

static VALUE
mitem_accelerator_text(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    char buf[1024];		/* enough? */

    gtk_menu_item_accelerator_text(GTK_MENU_ITEM(widget), buf);
    return str_new2(buf);
}

static VALUE
mitem_configure(self, show_toggle, show_submenu)
    VALUE self, show_toggle, show_submenu;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_item_configure(GTK_MENU_ITEM(widget), 
			    NUM2INT(show_toggle),
			    NUM2INT(show_submenu));
    return self;
}

static VALUE
mitem_select(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_item_select(GTK_MENU_ITEM(widget));
    return self;
}

static VALUE
mitem_deselect(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_item_deselect(GTK_MENU_ITEM(widget));
    return self;
}

static VALUE
mitem_activate(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_item_activate(GTK_MENU_ITEM(widget));
    return self;
}

static VALUE
mitem_right_justify(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_menu_item_right_justify(GTK_MENU_ITEM(widget));
    return self;
}

static VALUE
cmitem_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
{
    VALUE label;
    GtkWidget *widget;

    if (rb_scan_args(argc, argv, "01", &label) == 1) {
	widget = gtk_check_menu_item_new_with_label(STR2CSTR(label));
    }
    else {
	widget = gtk_check_menu_item_new();
    }

    set_widget(self, widget);
    return Qnil;
}

static VALUE
cmitem_set_state(self, state)
    VALUE self, state;
{
    GtkWidget *widget = get_widget(self);

    gtk_check_menu_item_set_state(GTK_CHECK_MENU_ITEM(widget), 
				  NUM2INT(state));
    return self;
}

static VALUE
cmitem_set_show_toggle(self, always)
    VALUE self, always;
{
    GtkWidget *widget = get_widget(self);

    gtk_check_menu_item_set_show_toggle(GTK_CHECK_MENU_ITEM(widget), 
					(gboolean)RTEST(always));
    return self;
}

static VALUE
cmitem_toggled(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_check_menu_item_toggled(GTK_CHECK_MENU_ITEM(widget));
    return self;
}

static VALUE
rmitem_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
{
    VALUE arg1, arg2;
    GtkWidget *widget;
    GSList *list = NULL;
    char *label = NULL;
    
    if (rb_scan_args(argc, argv, "02", &arg1, &arg2) == 1 &&
	TYPE(arg1) == T_STRING) {
	label = RSTRING(arg1)->ptr;
    }
    else {
	if (!NIL_P(arg2)) {
	    Check_Type(arg2, T_STRING);
	    label = RSTRING(arg2)->ptr;
	}
	if (obj_is_kind_of(arg1, gRMenuItem)) {
	    GtkWidget *b = get_widget(arg1);
	    list = GTK_RADIO_MENU_ITEM(b)->group;
	}
	else {
	    list = ary2gslist(arg1);
	}
    }
    if (label) {
	widget = gtk_radio_menu_item_new_with_label(list, label);
    }
    else {
	widget = gtk_radio_menu_item_new(list);
    }
    set_widget(self, widget);
    return Qnil;
}

static VALUE
rmitem_group(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    
    return gslist2ary(gtk_radio_menu_item_group(GTK_RADIO_MENU_ITEM(widget)));
}

static VALUE
note_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_notebook_new());
    return Qnil;
}

static VALUE
note_append_page(self, child, label)
    VALUE self, child, label;
{
    GtkWidget *widget = get_widget(self);

    gtk_notebook_append_page(GTK_NOTEBOOK(widget),
			     get_widget(child),
			     get_widget(label));
    return self;
}

static VALUE
note_prepend_page(self, child, label)
    VALUE self, child, label;
{
    GtkWidget *widget = get_widget(self);

    gtk_notebook_prepend_page(GTK_NOTEBOOK(widget),
			      get_widget(child),
			      get_widget(label));
    return self;
}

static VALUE
note_insert_page(self, child, label, pos)
    VALUE self, child, label, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_notebook_insert_page(GTK_NOTEBOOK(widget),
			     get_widget(child),
			     get_widget(label),
			     NUM2INT(pos));
    return self;
}

static VALUE
note_remove_page(self, pos)
    VALUE self, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_notebook_remove_page(GTK_NOTEBOOK(widget), NUM2INT(pos));
    return self;
}

static VALUE
note_set_page(self, pos)
    VALUE self, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_notebook_set_page(GTK_NOTEBOOK(widget), NUM2INT(pos));
    return self;
}

static VALUE
note_cur_page(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    return INT2FIX(GTK_NOTEBOOK(widget)->cur_page);
}

static VALUE
note_next_page(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_notebook_next_page(GTK_NOTEBOOK(widget));
    return self;
}

static VALUE
note_prev_page(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_notebook_prev_page(GTK_NOTEBOOK(widget));
    return self;
}

static VALUE
note_set_tab_pos(self, pos)
    VALUE self, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_notebook_set_tab_pos(GTK_NOTEBOOK(widget), NUM2INT(pos));
    return self;
}

static VALUE
note_tab_pos(self, pos)
    VALUE self, pos;
{
    GtkWidget *widget = get_widget(self);

    return INT2FIX(GTK_NOTEBOOK(widget)->tab_pos);
}

static VALUE
note_set_show_tabs(self, show_tabs)
    VALUE self, show_tabs;
{
    GtkWidget *widget = get_widget(self);

    gtk_notebook_set_tab_pos(GTK_NOTEBOOK(widget), RTEST(show_tabs));
    return self;
}

static VALUE
note_show_tabs(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    return GTK_NOTEBOOK(widget)->show_tabs?TRUE:FALSE;
}

static VALUE
note_set_show_border(self, show_border)
    VALUE self, show_border;
{
    GtkWidget *widget = get_widget(self);

    gtk_notebook_set_tab_pos(GTK_NOTEBOOK(widget), RTEST(show_border));
    return self;
}

static VALUE
note_show_border(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    return GTK_NOTEBOOK(widget)->show_border?TRUE:FALSE;
}

static VALUE
omenu_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_option_menu_new());
    return Qnil;
}

static VALUE
omenu_set_menu(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    rb_iv_set(self, "option_menu", child);
    gtk_option_menu_set_menu(GTK_OPTION_MENU(widget), get_widget(child));
    return self;
}

static VALUE
omenu_get_menu(self)
    VALUE self;
{
    return rb_iv_get(self, "option_menu");
}

static VALUE
omenu_remove_menu(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_option_menu_remove_menu(GTK_OPTION_MENU(widget));
    return self;
}

static VALUE
omenu_set_history(self, index)
    VALUE self, index;
{
    GtkWidget *widget = get_widget(self);

    gtk_option_menu_set_history(GTK_OPTION_MENU(widget), NUM2INT(index));
    return self;
}

static VALUE
image_initialize(self, val, mask)
    VALUE self, val, mask;
{
    set_widget(self, gtk_image_new(get_gdkimage(val),
				   (GdkBitmap*)get_gdkpixmap(mask)));
    return Qnil;
}

static VALUE
image_set(self, val, mask)
    VALUE self, val, mask;
{
    GtkWidget *widget = get_widget(self);

    gtk_image_set(GTK_IMAGE(widget), get_gdkimage(val), get_gdkpixmap(mask));
    return self;
}

static VALUE
image_get(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    GdkImage  *val;
    GdkBitmap *mask;

    gtk_image_get(GTK_IMAGE(widget), &val, &mask);

    return assoc_new(make_gdkimage(self, val),
		     make_gdkpixmap(self, mask));
}

static VALUE
preview_initialize(self, type)
    VALUE self, type;
{
    set_widget(self, gtk_preview_new((GtkPreviewType)NUM2INT(type)));
    return Qnil;
}


static VALUE
preview_size(self, w, h)
    VALUE self, w, h;
{
    GtkWidget *widget = get_widget(self);

    gtk_preview_size(GTK_PREVIEW(widget), NUM2INT(w), NUM2INT(h));
    return self;
}

#if 0
    rb_define_method(gPixmap, "put", preview_size, 8);
    rb_define_method(gPixmap, "put_row", preview_size, 5);
    rb_define_method(gPixmap, "draw_row", preview_size, 4);
#endif

static VALUE
preview_set_expand(self, expand)
    VALUE self, expand;
{
    GtkWidget *widget = get_widget(self);

    gtk_preview_set_expand(GTK_PREVIEW(widget), NUM2INT(expand));
    return self;
}

static VALUE
preview_set_gamma(self, gamma)
    VALUE self, gamma;
{
    gtk_preview_set_gamma(NUM2DBL(gamma));
    return Qnil;
}

static VALUE
preview_set_color_cube(self, nred, ngreen, nblue, ngray)
    VALUE self, nred, ngreen, nblue, ngray;
{
    gtk_preview_set_color_cube(NUM2INT(nred),
			       NUM2INT(ngreen),
			       NUM2INT(nblue),
			       NUM2INT(ngray));
    return Qnil;
}

static VALUE
preview_set_install_cmap(self, cmap)
    VALUE self, cmap;
{
    gtk_preview_set_install_cmap(NUM2INT(cmap));
    return Qnil;
}

static VALUE
preview_set_reserved(self, nreserved)
    VALUE self, nreserved;
{
    gtk_preview_set_reserved(NUM2INT(nreserved));
    return Qnil;
}

static VALUE
preview_get_visual(self)
    VALUE self;
{
    GdkVisual *v = gtk_preview_get_visual();
    return make_gdkvisual(v);
}

static VALUE
preview_get_cmap(self)
    VALUE self;
{
    GdkColormap *c = gtk_preview_get_cmap();
    return make_gdkcmap(c);
}

static VALUE
preview_get_info(self)
    VALUE self;
{
    GtkPreviewInfo *i = gtk_preview_get_info();
    return make_gtkprevinfo(i);
}

static VALUE
pbar_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_progress_bar_new());
    return Qnil;
}

static VALUE
pbar_update(self, percentage)
    VALUE self, percentage;
{
    GtkWidget *widget = get_widget(self);

    gtk_progress_bar_update(GTK_PROGRESS_BAR(widget),
			    NUM2DBL(percentage));
    return self;
}    

static VALUE
scwin_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE arg1, arg2;
    GtkAdjustment *h_adj = NULL;
    GtkAdjustment *v_adj = NULL;

    rb_scan_args(argc, argv, "02", &arg1, &arg2);
    if (!NIL_P(arg1)) h_adj = (GtkAdjustment*)get_gobject(arg1);
    if (!NIL_P(arg2)) v_adj = (GtkAdjustment*)get_gobject(arg2);

    set_widget(self, gtk_scrolled_window_new(h_adj, v_adj));
    return Qnil;
}

static VALUE
scwin_set_policy(self, hpolicy, vpolicy)
    VALUE self, hpolicy, vpolicy;
{
    GtkWidget *widget = get_widget(self);

    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(widget),
				   (GtkPolicyType)NUM2INT(hpolicy),
				   (GtkPolicyType)NUM2INT(vpolicy));
    return self;
}


static VALUE
tbl_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
{
    VALUE row, col, homogeneous;

    rb_scan_args(argc, argv, "21", &row, &col, &homogeneous);
    set_widget(self, gtk_table_new(NUM2INT(row),
					   NUM2INT(col),
					   RTEST(homogeneous)));
    return Qnil;
}

static VALUE
tbl_attach(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    VALUE child, left, right, top, bottom;
    VALUE arg0, arg1, arg2, arg3;
    int xopt, yopt, xspc, yspc;

    xopt = yopt = GTK_EXPAND | GTK_FILL;
    xspc = yspc = 0;
    rb_scan_args(argc, argv, "54",
		 &child, &left, &right, &top, &bottom,
		 &arg0, &arg1, &arg2, &arg3);
    if (!NIL_P(arg0)) xopt = NUM2INT(arg0);
    if (!NIL_P(arg1)) yopt = NUM2INT(arg1);
    if (!NIL_P(arg2)) xspc = NUM2INT(arg2);
    if (!NIL_P(arg3)) yspc = NUM2INT(arg3);

    gtk_table_attach(GTK_TABLE(widget),
		     get_widget(child),
		     NUM2INT(left),NUM2INT(right),
		     NUM2INT(top),NUM2INT(bottom),
		     xopt, yopt, xspc, yspc);

    return self;
}

static VALUE
tbl_set_row_spacing(self, row, spc)
    VALUE self, row, spc;
{
    GtkWidget *widget = get_widget(self);

    gtk_table_set_row_spacing(GTK_TABLE(widget), NUM2INT(row), NUM2INT(spc));
    return self;
}

static VALUE
tbl_set_col_spacing(self, col, spc)
    VALUE self, col, spc;
{
    GtkWidget *widget = get_widget(self);

    gtk_table_set_col_spacing(GTK_TABLE(widget), NUM2INT(col), NUM2INT(spc));
    return self;
}

static VALUE
tbl_set_row_spacings(self, spc)
    VALUE self, spc;
{
    GtkWidget *widget = get_widget(self);

    gtk_table_set_row_spacings(GTK_TABLE(widget), NUM2INT(spc));
    return self;
}

static VALUE
tbl_set_col_spacings(self, spc)
    VALUE self, spc;
{
    GtkWidget *widget = get_widget(self);

    gtk_table_set_col_spacings(GTK_TABLE(widget), NUM2INT(spc));
    return self;
}

static VALUE
txt_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE arg1, arg2;
    GtkAdjustment *h_adj = NULL;
    GtkAdjustment *v_adj = NULL;

    rb_scan_args(argc, argv, "02", &arg1, &arg2);
    if (!NIL_P(arg1)) h_adj = (GtkAdjustment*)get_gobject(arg1);
    if (!NIL_P(arg2)) v_adj = (GtkAdjustment*)get_gobject(arg2);

    set_widget(self, gtk_text_new(h_adj, v_adj));
    return Qnil;
}

static VALUE
txt_set_editable(self, editable)
    VALUE self, editable;
{
    GtkWidget *widget = get_widget(self);

    gtk_text_set_editable(GTK_TEXT(widget), RTEST(editable));
    return self;
}

static VALUE
txt_set_adjustment(self, h_adj, v_adj)
    VALUE self, h_adj, v_adj;
{
    GtkWidget *widget = get_widget(self);

    gtk_text_set_adjustments(GTK_TEXT(widget),
			     (GtkAdjustment*)get_gobject(h_adj),
			     (GtkAdjustment*)get_gobject(v_adj));

    return self;
}

static VALUE
txt_set_point(self, index)
    VALUE self, index;
{
    GtkWidget *widget = get_widget(self);

    gtk_text_set_point(GTK_TEXT(widget), NUM2INT(index));
    return self;
}

static VALUE
txt_get_point(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    int index = gtk_text_get_point(GTK_TEXT(widget));
    
    return INT2FIX(index);
}

static VALUE
txt_get_length(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    int len = gtk_text_get_length(GTK_TEXT(widget));
    
    return INT2FIX(len);
}

static VALUE
txt_freeze(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_text_freeze(GTK_TEXT(widget));
    return self;
}

static VALUE
txt_thaw(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_text_thaw(GTK_TEXT(widget));
    return self;
}

static VALUE
txt_insert(self, font, fore, back, str)
    VALUE self, font, fore, back, str;
{
    GtkWidget *widget = get_widget(self);

    Check_Type(str, T_STRING);
    gtk_text_insert(GTK_TEXT(widget), 
		    get_gdkfont(font),
		    get_gdkcolor(fore),
		    get_gdkcolor(back),
		    RSTRING(str)->ptr,
		    RSTRING(str)->len);

    return self;
}

static VALUE
txt_backward_delete(self, nchars)
    VALUE self, nchars;
{
    GtkWidget *widget = get_widget(self);

    gtk_text_backward_delete(GTK_TEXT(widget), NUM2INT(nchars));
    return self;
}

static VALUE
txt_forward_delete(self, nchars)
    VALUE self, nchars;
{
    GtkWidget *widget = get_widget(self);

    gtk_text_forward_delete(GTK_TEXT(widget), NUM2INT(nchars));
    return self;
}

static VALUE
tbar_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE arg1, arg2;
    GtkOrientation orientation = GTK_ORIENTATION_HORIZONTAL;
    GtkToolbarStyle style = GTK_TOOLBAR_BOTH;

    rb_scan_args(argc, argv, "02", &arg1, &arg2);
    if (!NIL_P(arg1)) orientation = (GtkOrientation)NUM2INT(arg1);
    if (!NIL_P(arg2)) style = (GtkToolbarStyle)NUM2INT(arg2);

    set_widget(self, gtk_toolbar_new(orientation, style));
    return Qnil;
}

static VALUE
tbar_append_item(self, text, ttext, icon, func)
    VALUE self, text, ttext, icon, func;
{
    GtkWidget *widget = get_widget(self);

    if (NIL_P(func)) {
	func = f_lambda();
    }
    gtk_toolbar_append_item(GTK_TOOLBAR(widget),
			    STR2CSTR(text),
			    STR2CSTR(ttext),
			    get_widget(icon),
			    exec_callback,
			    (gpointer)ary_new3(1, func));
    return self;
}

static VALUE
tbar_prepend_item(self, text, ttext, icon, func)
    VALUE self, text, ttext, icon, func;
{
    GtkWidget *widget = get_widget(self);

    if (NIL_P(func)) {
	func = f_lambda();
    }
    gtk_toolbar_prepend_item(GTK_TOOLBAR(widget),
			     STR2CSTR(text),
			     STR2CSTR(ttext),
			     get_widget(icon),
			     exec_callback,
			     (gpointer)ary_new3(1, func));
    return self;
}

static VALUE
tbar_insert_item(self, text, ttext, icon, func, pos)
    VALUE self, text, ttext, icon, func, pos;
{
    GtkWidget *widget = get_widget(self);

    if (NIL_P(func)) {
	func = f_lambda();
    }
    gtk_toolbar_insert_item(GTK_TOOLBAR(widget),
			    STR2CSTR(text),
			    STR2CSTR(ttext),
			    get_widget(icon),
			    exec_callback,
			    (gpointer)ary_new3(1, func),
			    NUM2INT(pos));
    return self;
}

static VALUE
tbar_append_space(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_toolbar_append_space(GTK_TOOLBAR(widget));
    return self;
}

static VALUE
tbar_prepend_space(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_toolbar_prepend_space(GTK_TOOLBAR(widget));
    return self;
}

static VALUE
tbar_insert_space(self, pos)
    VALUE self, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_toolbar_insert_space(GTK_TOOLBAR(widget), NUM2INT(pos));
    return self;
}

static VALUE
tbar_set_orientation(self, orientation)
    VALUE self, orientation;
{
    GtkWidget *widget = get_widget(self);

    gtk_toolbar_set_orientation(GTK_TOOLBAR(widget), 
				(GtkOrientation)NUM2INT(orientation));
    return self;
}

static VALUE
tbar_set_style(self, style)
    VALUE self, style;
{
    GtkWidget *widget = get_widget(self);

    gtk_toolbar_set_style(GTK_TOOLBAR(widget), 
			  (GtkToolbarStyle)NUM2INT(style));
    return self;
}

static VALUE
tbar_set_space_size(self, size)
    VALUE self, size;
{
    GtkWidget *widget = get_widget(self);

    gtk_toolbar_set_space_size(GTK_TOOLBAR(widget), NUM2INT(size));
    return self;
}

static VALUE
tbar_set_tooltips(self, enable)
    VALUE self, enable;
{
    GtkWidget *widget = get_widget(self);

    gtk_toolbar_set_tooltips(GTK_TOOLBAR(widget), RTEST(enable));
    return self;
}

static VALUE
ttips_initialize(self)
    VALUE self;
{
    return make_ttips(self, gtk_tooltips_new());
}

static VALUE
ttips_set_tips(self, win, text)
    VALUE self, win, text;
{
    Check_Type(text, T_STRING);
    gtk_tooltips_set_tips(get_ttips(self),
			  get_widget(win),
			  RSTRING(text)->ptr);

    return self;
}

static VALUE
ttips_set_delay(self, delay)
    VALUE self, delay;
{
    gtk_tooltips_set_delay(get_ttips(self), NUM2INT(delay));

    return self;
}

static VALUE
ttips_enable(self)
    VALUE self;
{
    gtk_tooltips_enable(get_ttips(self));
    return self;
}

static VALUE
ttips_disable(self)
    VALUE self;
{
    gtk_tooltips_enable(get_ttips(self));
    return self;
}

static VALUE
tree_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_tree_new());
    return Qnil;
}

static VALUE
tree_append(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    gtk_tree_append(GTK_TREE(widget), get_widget(child));
    return self;
}

static VALUE
tree_prepend(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    gtk_tree_prepend(GTK_TREE(widget), get_widget(child));
    return self;
}

static VALUE
tree_insert(self, child, pos)
    VALUE self, child, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_tree_insert(GTK_TREE(widget), get_widget(child), NUM2INT(pos));
    return self;
}

static VALUE
titem_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
{
    VALUE label;
    GtkWidget *widget;

    if (rb_scan_args(argc, argv, "01", &label) == 1) {
	Check_Type(label, T_STRING);
	widget = gtk_tree_item_new_with_label(RSTRING(label)->ptr);
    }
    else {
	widget = gtk_tree_item_new();
    }

    set_widget(self, widget);
    return Qnil;
}

static VALUE
titem_set_subtree(self, subtree)
    VALUE self, subtree;
{
    GtkWidget *widget = get_widget(self);

    gtk_tree_item_set_subtree(GTK_TREE_ITEM(widget), get_widget(subtree));
    return self;
}

static VALUE
titem_select(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_tree_item_select(GTK_TREE_ITEM(widget));
    return self;
}

static VALUE
titem_deselect(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_tree_item_deselect(GTK_TREE_ITEM(widget));
    return self;
}

static VALUE
titem_expand(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_tree_item_expand(GTK_TREE_ITEM(widget));
    return self;
}

static VALUE
titem_collapse(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_tree_item_collapse(GTK_TREE_ITEM(widget));
    return self;
}

static VALUE
vport_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE arg1, arg2;
    GtkAdjustment *h_adj = NULL;
    GtkAdjustment *v_adj = NULL;

    rb_scan_args(argc, argv, "02", &arg1, &arg2);
    if (!NIL_P(arg1)) h_adj = (GtkAdjustment*)get_gobject(arg1);
    if (!NIL_P(arg2)) v_adj = (GtkAdjustment*)get_gobject(arg2);

    set_widget(self, gtk_viewport_new(h_adj, v_adj));
    return Qnil;
}

static VALUE
vport_get_hadj(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    GtkAdjustment *adj = gtk_viewport_get_hadjustment(GTK_VIEWPORT(widget));

    return make_gobject(gAdjustment, GTK_OBJECT(adj));
}

static VALUE
vport_get_vadj(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    GtkAdjustment *adj = gtk_viewport_get_vadjustment(GTK_VIEWPORT(widget));

    return make_gobject(gAdjustment, GTK_OBJECT(adj));
}

static VALUE
vport_set_vadj(self, adj)
    VALUE self, adj;
{
    GtkWidget *widget = get_widget(self);
    GtkObject *adjustment = get_gobject(adj);

    gtk_viewport_set_vadjustment(GTK_VIEWPORT(widget),
				 GTK_ADJUSTMENT(adj));

    return self;
}

static VALUE
vport_set_hadj(self, adj)
    VALUE self, adj;
{
    GtkWidget *widget = get_widget(self);
    GtkObject *adjustment = get_gobject(adj);

    gtk_viewport_set_hadjustment(GTK_VIEWPORT(widget),
				 GTK_ADJUSTMENT(adj));

    return self;
}

static VALUE
vport_set_shadow(self, type)
    VALUE self, type;
{
    GtkWidget *widget = get_widget(self);

    gtk_viewport_set_shadow_type(GTK_VIEWPORT(widget),
				 (GtkShadowType)NUM2INT(type));

    return self;
}

static VALUE
button_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
{
    VALUE label;
    GtkWidget *widget;

    if (rb_scan_args(argc, argv, "01", &label) == 1) {
	Check_Type(label, T_STRING);
	widget = gtk_button_new_with_label(RSTRING(label)->ptr);
    }
    else {
	widget = gtk_button_new();
    }

    set_widget(self, widget);
    return Qnil;
}

static VALUE
button_pressed(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_button_pressed(GTK_BUTTON(widget));
    return self;
}

static VALUE
button_released(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_button_released(GTK_BUTTON(widget));
    return self;
}

static VALUE
button_clicked(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_button_clicked(GTK_BUTTON(widget));
    return self;
}

static VALUE
button_enter(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_button_enter(GTK_BUTTON(widget));
    return self;
}

static VALUE
button_leave(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_button_leave(GTK_BUTTON(widget));
    return self;
}

static VALUE
tbtn_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
{
    VALUE label;
    GtkWidget *widget;

    if (rb_scan_args(argc, argv, "01", &label) == 1) {
	Check_Type(label, T_STRING);
	widget = gtk_toggle_button_new_with_label(RSTRING(label)->ptr);
    }
    else {
	widget = gtk_toggle_button_new();
    }

    set_widget(self, widget);
    return Qnil;
}

static VALUE
tbtn_set_mode(self, mode)
    VALUE self, mode;
{
    GtkWidget *widget = get_widget(self);

    gtk_toggle_button_set_mode(GTK_TOGGLE_BUTTON(widget), NUM2INT(mode));
    return self;
}

static VALUE
tbtn_set_state(self, state)
    VALUE self, state;
{
    GtkWidget *widget = get_widget(self);

    gtk_toggle_button_set_state(GTK_TOGGLE_BUTTON(widget), NUM2INT(state));
    return self;
}

static VALUE
tbtn_toggled(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_toggle_button_toggled(GTK_TOGGLE_BUTTON(widget));
    return self;
}

static VALUE
cbtn_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
{
    VALUE label;
    GtkWidget *widget;

    if (rb_scan_args(argc, argv, "01", &label) == 1) {
	Check_Type(label, T_STRING);
	widget = gtk_check_button_new_with_label(RSTRING(label)->ptr);
    }
    else {
	widget = gtk_check_button_new();
    }

    set_widget(self, widget);
    return Qnil;
}

static VALUE
rbtn_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
{
    VALUE arg1, arg2;
    GtkWidget *widget;
    GSList *list = NULL;
    char *label = NULL;
    
    if (rb_scan_args(argc, argv, "02", &arg1, &arg2) == 1 &&
	TYPE(arg1) == T_STRING) {
	label = RSTRING(arg1)->ptr;
    }
    else {
	if (!NIL_P(arg2)) {
	    Check_Type(arg2, T_STRING);
	    label = RSTRING(arg2)->ptr;
	}
	if (obj_is_kind_of(arg1, gRButton)) {
	    GtkWidget *b = get_widget(arg1);
	    list = GTK_RADIO_BUTTON(b)->group;
	}
	else {
	    list = ary2gslist(arg1);
	}
    }
    if (label) {
	widget = gtk_radio_button_new_with_label(list, label);
    }
    else {
	widget = gtk_radio_button_new(list);
    }
    set_widget(self, widget);
    return Qnil;
}

static VALUE
rbtn_group(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    
    return gslist2ary(gtk_radio_button_group(GTK_RADIO_BUTTON(widget)));
}

static void
box_pack_start_or_end(argc, argv, self, start)
    int argc;
    VALUE *argv;
    VALUE self;
    int start;
{
    VALUE arg0, arg1, arg2, arg3;
    gint expand, fill, padding;
    GtkWidget *widget, *child;

    expand = fill = TRUE; padding = 0;
    switch (rb_scan_args(argc, argv, "13", &arg0, &arg1, &arg2, &arg3)) {
      case 4:
	padding = NUM2INT(arg3);
      case 3:
	fill = RTEST(arg2);
      case 2:
	expand = RTEST(arg1);
      default:
	child = get_widget(arg0);
	break;
    }
    widget = get_widget(self);

    if (start)
	gtk_box_pack_start(GTK_BOX(widget), child, expand, fill, padding);
    else
	gtk_box_pack_end(GTK_BOX(widget), child, expand, fill, padding);
}

static VALUE
box_pack_start(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    box_pack_start_or_end(argc, argv, self, 1);
    return self;
}

static VALUE
box_pack_end(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    box_pack_start_or_end(argc, argv, self, 0);
    return self;
}

static VALUE
vbox_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE homogeneous, spacing;
    GtkWidget *widget;

    rb_scan_args(argc, argv, "02", &homogeneous, &spacing);
    widget = gtk_vbox_new(RTEST(homogeneous), NUM2INT(spacing));

    set_widget(self, widget);
    return Qnil;
}

static VALUE
colorsel_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_color_selection_new());
    return Qnil;
}

static VALUE
colorsel_set_update_policy(self, policy)
    VALUE self, policy;
{
    GtkWidget *widget = get_widget(self);

    gtk_color_selection_set_update_policy(GTK_COLOR_SELECTION(widget),
					  (GtkUpdateType)NUM2INT(policy));
    return self;
}

static VALUE
colorsel_set_opacity(self, opacity)
    VALUE self, opacity;
{
    GtkWidget *widget = get_widget(self);

    gtk_color_selection_set_opacity(GTK_COLOR_SELECTION(widget),
				    RTEST(opacity));
    return self;
}

static VALUE
colorsel_set_color(self, color)
    VALUE self, color;
{
    GtkWidget *widget = get_widget(self);
    double buf[3];

    Check_Type(color, T_ARRAY);
    if (RARRAY(color)->len < 3) {
	ArgError("color array too small");
    }
    buf[0] = NUM2DBL(RARRAY(color)->ptr[0]);
    buf[1] = NUM2DBL(RARRAY(color)->ptr[1]);
    buf[2] = NUM2DBL(RARRAY(color)->ptr[2]);

    gtk_color_selection_set_color(GTK_COLOR_SELECTION(widget), buf);
    return self;
}

static VALUE
colorsel_get_color(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    double buf[3];
    VALUE ary;

    gtk_color_selection_get_color(GTK_COLOR_SELECTION(widget), buf);
    ary = ary_new2(3);
    ary_push(ary, NUM2DBL(buf[0]));
    ary_push(ary, NUM2DBL(buf[1]));
    ary_push(ary, NUM2DBL(buf[2]));
    return ary;
}

static VALUE
cdialog_initialize(self, title)
    VALUE self;
{
    char *t;

    Check_Type(title, T_STRING);
    t = RSTRING(title)->ptr;
    set_widget(self, gtk_color_selection_dialog_new(t));
    return Qnil;
}

static VALUE
pixmap_initialize(self, val, mask)
    VALUE self, val, mask;
{
    set_widget(self, gtk_pixmap_new(get_gdkpixmap(val),
					    get_gdkpixmap(mask)));
    return Qnil;
}

static VALUE
pixmap_set(self, val, mask)
    VALUE self, val, mask;
{
    GtkWidget *widget = get_widget(self);

    gtk_pixmap_set(GTK_PIXMAP(widget),
		   get_gdkpixmap(val), get_gdkpixmap(mask));
    return self;
}

static VALUE
pixmap_get(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    GdkPixmap  *val;
    GdkBitmap *mask;

    gtk_pixmap_get(GTK_PIXMAP(widget), &val, &mask);

    return assoc_new(make_gdkpixmap(self, val),
		     make_gdkpixmap(self, mask));
}

static VALUE
darea_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_drawing_area_new());
    return Qnil;
}

static VALUE
darea_size(self, w, h)
    VALUE self, w, h;
{
    GtkWidget *widget = get_widget(self);

    gtk_drawing_area_size(GTK_DRAWING_AREA(widget), NUM2INT(w), NUM2INT(h));
    return self;
}

static VALUE
entry_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_entry_new());
    return Qnil;
}

static VALUE
entry_set_text(self, text)
    VALUE self, text;
{
    GtkWidget *widget = get_widget(self);

    Check_Type(text, T_STRING);
    gtk_entry_set_text(GTK_ENTRY(widget), RSTRING(text)->ptr);

    return self;
}

static VALUE
eventbox_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_event_box_new());
    return Qnil;
}

static VALUE
fixed_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_fixed_new());
    return Qnil;
}

static VALUE
fixed_put(self, win, x, y)
    VALUE self, win, x, y;
{
    GtkWidget *widget = get_widget(self);

    gtk_fixed_put(GTK_FIXED(widget), get_widget(win), NUM2INT(x), NUM2INT(y));
    return self;
}

static VALUE
fixed_move(self, win, x, y)
    VALUE self, win, x, y;
{
    GtkWidget *widget = get_widget(self);

    gtk_fixed_move(GTK_FIXED(widget), get_widget(win), NUM2INT(x), NUM2INT(y));
    return self;
}

static VALUE
gamma_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_gamma_curve_new());
    return Qnil;
}

static VALUE
gamma_gamma(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    return float_new(GTK_GAMMA_CURVE(widget)->gamma);
}

static VALUE
hbbox_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_hbutton_box_new());
    return Qnil;
}

static VALUE
hbbox_get_spacing_default(self)
    VALUE self;
{
    int n = gtk_hbutton_box_get_spacing_default();
    
    return INT2FIX(n);
}

static VALUE
hbbox_get_layout_default(self)
    VALUE self;
{
    int n = gtk_hbutton_box_get_layout_default();
    
    return INT2FIX(n);
}

static VALUE
hbbox_set_spacing_default(self, spacing)
    VALUE self, spacing;
{
    gtk_hbutton_box_set_spacing_default(NUM2INT(spacing));
    return Qnil;
}

static VALUE
hbbox_set_layout_default(self, layout)
    VALUE self, layout;
{
    gtk_hbutton_box_set_layout_default(NUM2INT(layout));
    return Qnil;
}

static VALUE
vbbox_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_vbutton_box_new());
    return Qnil;
}

static VALUE
vbbox_get_spacing_default(self)
    VALUE self;
{
    int n = gtk_vbutton_box_get_spacing_default();
    
    return INT2FIX(n);
}

static VALUE
vbbox_get_layout_default(self)
    VALUE self;
{
    int n = gtk_vbutton_box_get_layout_default();
    
    return INT2FIX(n);
}

static VALUE
vbbox_set_spacing_default(self, spacing)
    VALUE self, spacing;
{
    gtk_vbutton_box_set_spacing_default(NUM2INT(spacing));
    return Qnil;
}

static VALUE
vbbox_set_layout_default(self, layout)
    VALUE self, layout;
{
    gtk_vbutton_box_set_layout_default(NUM2INT(layout));
    return Qnil;
}

static VALUE
hbox_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE homogeneous, spacing;
    GtkWidget *widget;

    rb_scan_args(argc, argv, "02", &homogeneous, &spacing);
    widget = gtk_hbox_new(RTEST(homogeneous), NUM2INT(spacing));

    set_widget(self, widget);
    return Qnil;
}

static VALUE
paned_add1(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    gtk_paned_add1(GTK_PANED(widget), get_widget(child));
    return self;
}

static VALUE
paned_add2(self, child)
    VALUE self, child;
{
    GtkWidget *widget = get_widget(self);

    gtk_paned_add2(GTK_PANED(widget), get_widget(child));
    return self;
}

static VALUE
paned_handle_size(self, size)
    VALUE self, size;
{
    GtkWidget *widget = get_widget(self);

    gtk_paned_handle_size(GTK_PANED(widget), NUM2INT(size));
    return self;
}

static VALUE
paned_gutter_size(self, size)
    VALUE self, size;
{
    GtkWidget *widget = get_widget(self);

    gtk_paned_gutter_size(GTK_PANED(widget), NUM2INT(size));
    return self;
}

static VALUE
hpaned_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_hpaned_new());
    return Qnil;
}

static VALUE
vpaned_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_vpaned_new());
    return Qnil;
}

static VALUE
ruler_set_metric(self, metric)
    VALUE self, metric;
{
    GtkWidget *widget = get_widget(self);

    gtk_ruler_set_metric(GTK_RULER(widget), 
			 (GtkMetricType)NUM2INT(metric));

    return self;
}

static VALUE
ruler_set_range(self, lower, upper, position, max_size)
    VALUE self, lower, upper, position, max_size;
{
    GtkWidget *widget = get_widget(self);

    gtk_ruler_set_range(GTK_RULER(widget), 
			NUM2DBL(lower), NUM2DBL(upper),
			NUM2DBL(position), NUM2DBL(max_size));

    return self;
}

static VALUE
ruler_draw_ticks(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_ruler_draw_ticks(GTK_RULER(widget));
    return self;
}

static VALUE
ruler_draw_pos(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_ruler_draw_pos(GTK_RULER(widget));
    return self;
}

static VALUE
hruler_initialize(self)
{
    set_widget(self, gtk_hruler_new());
    return Qnil;
}

static VALUE
vruler_initialize(self)
{
    set_widget(self, gtk_vruler_new());
    return Qnil;
}

static VALUE
range_get_adj(self)
{
    GtkWidget *widget = get_widget(self);
    GtkAdjustment *adj = gtk_range_get_adjustment(GTK_RANGE(widget));

    return make_gobject(gAdjustment, GTK_OBJECT(adj));
}

static VALUE
range_set_update_policy(self, policy)
    VALUE self, policy;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_set_update_policy(GTK_RANGE(widget),
				(GtkUpdateType)NUM2INT(policy));
    return self;
}

static VALUE
range_set_adj(self, adj)
    VALUE self, adj;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_set_adjustment(GTK_RANGE(widget),
			     (GtkAdjustment*)get_gobject(adj));

    return self;
}

static VALUE
range_draw_bg(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_draw_background(GTK_RANGE(widget));
    return self;
}

static VALUE
range_draw_trough(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_draw_trough(GTK_RANGE(widget));
    return self;
}

static VALUE
range_draw_slider(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_draw_slider(GTK_RANGE(widget));
    return self;
}

static VALUE
range_draw_step_forw(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_draw_step_forw(GTK_RANGE(widget));
    return self;
}

static VALUE
range_draw_step_back(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_draw_step_back(GTK_RANGE(widget));
    return self;
}

static VALUE
range_slider_update(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_slider_update(GTK_RANGE(widget));
    return self;
}

static VALUE
range_trough_click(self, x, y)
    VALUE self, x, y;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_trough_click(GTK_RANGE(widget), NUM2INT(x), NUM2INT(y));
    return self;
}

static VALUE
range_default_hslider_update(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_default_hslider_update(GTK_RANGE(widget));
    return self;
}

static VALUE
range_default_vslider_update(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_default_vslider_update(GTK_RANGE(widget));
    return self;
}

static VALUE
range_default_htrough_click(self, x, y)
    VALUE self, x, y;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_default_htrough_click(GTK_RANGE(widget),
				    NUM2INT(x), NUM2INT(y));
    return self;
}

static VALUE
range_default_vtrough_click(self, x, y)
    VALUE self, x, y;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_default_vtrough_click(GTK_RANGE(widget),
				    NUM2INT(x), NUM2INT(y));
    return self;
}

static VALUE
range_default_hmotion(self, xdelta, ydelta)
    VALUE self, xdelta, ydelta;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_default_hmotion(GTK_RANGE(widget),
			      NUM2INT(xdelta), NUM2INT(ydelta));
    return self;
}

static VALUE
range_default_vmotion(self, xdelta, ydelta)
    VALUE self, xdelta, ydelta;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_default_vmotion(GTK_RANGE(widget),
			      NUM2INT(xdelta), NUM2INT(ydelta));
    return self;
}

static VALUE
range_calc_value(self, pos)
    VALUE self, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_range_calc_value(GTK_RANGE(widget), NUM2INT(pos));
    return self;
}

static VALUE
scale_set_digits(self, digits)
    VALUE self, digits;
{
    GtkWidget *widget = get_widget(self);

    gtk_scale_set_digits(GTK_SCALE(widget), NUM2INT(digits));
    return self;
}

static VALUE
scale_set_draw_value(self, draw_value)
    VALUE self, draw_value;
{
    GtkWidget *widget = get_widget(self);

    gtk_scale_set_draw_value(GTK_SCALE(widget), NUM2INT(draw_value));
    return self;
}

static VALUE
scale_set_value_pos(self, pos)
    VALUE self, pos;
{
    GtkWidget *widget = get_widget(self);

    gtk_scale_set_value_pos(GTK_SCALE(widget), 
			    (GtkPositionType)NUM2INT(pos));
    return self;
}

static VALUE
scale_value_width(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);
    int i = gtk_scale_value_width(GTK_SCALE(widget));

    return INT2FIX(i);
}

static VALUE
scale_draw_value(self)
    VALUE self;
{
    GtkWidget *widget = get_widget(self);

    gtk_scale_draw_value(GTK_SCALE(widget));
    return self;
}

static VALUE
hscale_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE arg1;
    GtkAdjustment *adj = NULL;

    rb_scan_args(argc, argv, "01", &arg1);
    if (!NIL_P(arg1)) adj = (GtkAdjustment*)get_gobject(arg1);

    set_widget(self, gtk_hscale_new(adj));
    return Qnil;
}

static VALUE
vscale_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE arg1;
    GtkAdjustment *adj = NULL;

    rb_scan_args(argc, argv, "01", &arg1);
    if (!NIL_P(arg1)) adj = (GtkAdjustment*)get_gobject(arg1);

    set_widget(self, gtk_vscale_new(adj));
    return Qnil;
}

static VALUE
hscrollbar_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE arg1;
    GtkAdjustment *adj = NULL;

    rb_scan_args(argc, argv, "01", &arg1);
    if (!NIL_P(arg1)) adj = (GtkAdjustment*)get_gobject(arg1);

    set_widget(self, gtk_hscrollbar_new(adj));
    return Qnil;
}

static VALUE
vscrollbar_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE arg1;
    GtkAdjustment *adj = NULL;

    rb_scan_args(argc, argv, "01", &arg1);
    if (!NIL_P(arg1)) adj = (GtkAdjustment*)get_gobject(arg1);

    set_widget(self, gtk_vscrollbar_new(adj));
    return Qnil;
}

static VALUE
hsep_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_hseparator_new());
    return Qnil;
}

static VALUE
vsep_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_vseparator_new());
    return Qnil;
}

static VALUE
idiag_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_input_dialog_new());
    return Qnil;
}

static VALUE
gtk_m_main(self)
    VALUE self;
{
    gtk_main();
    return Qnil;
}

static gint
idle()
{
    CHECK_INTS;
    return TRUE;
}

static void
exec_interval(proc)
    VALUE proc;
{
    rb_funcall(proc, id_call, 0);
}

static VALUE
timeout_add(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE interval, func;
    int id;

    rb_scan_args(argc, argv, "11", &interval, &func);
    if (NIL_P(func)) {
	func = f_lambda();
    }
    id = gtk_timeout_add_interp(NUM2INT(interval), exec_interval,
				(gpointer)func, 0);
    return INT2FIX(id);
}

static VALUE
timeout_remove(self, id)
    VALUE self, id;
{
    gtk_timeout_remove(NUM2INT(id));
    return Qnil;
}

static VALUE
idle_add(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE func;
    int id;

    rb_scan_args(argc, argv, "01", &func);
    if (NIL_P(func)) {
	func = f_lambda();
    }
    id = gtk_idle_add_interp(exec_interval, (gpointer)func, 0);
    return INT2FIX(id);
}

static VALUE
idle_remove(self, id)
    VALUE self, id;
{
    gtk_idle_remove(NUM2INT(id));
    return Qnil;
}

static VALUE warn_handler;
static VALUE mesg_handler;
static VALUE print_handler;

static void
gtkwarn(mesg)
    char *mesg;
{
    rb_funcall(warn_handler, id_call, 1, str_new2(mesg));
}

static void
gtkmesg(mesg)
    char *mesg;
{
    rb_funcall(mesg_handler, id_call, 1, str_new2(mesg));
}

static void
gtkprint(mesg)
    char *mesg;
{
    rb_funcall(print_handler, id_call, 1, str_new2(mesg));
}

static VALUE
set_warning_handler(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE handler;

    rb_scan_args(argc, argv, "01", &handler);
    if (NIL_P(handler)) {
	handler = f_lambda();
    }
    g_set_warning_handler(gtkwarn);
}

static VALUE
set_message_handler(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE handler;

    rb_scan_args(argc, argv, "01", &handler);
    if (NIL_P(handler)) {
	handler = f_lambda();
    }
    g_set_message_handler(gtkmesg);
}

static VALUE
set_print_handler(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE handler;

    rb_scan_args(argc, argv, "01", &handler);
    if (NIL_P(handler)) {
	handler = f_lambda();
    }
    g_set_print_handler(gtkprint);
}

static void
gtkerr(mesg)
    char *mesg;
{
    Fail("%s", mesg);
}

void
Init_gtk()
{
    int argc, i;
    char **argv;

    gtk_object_list = ary_new();
    rb_global_variable(&gtk_object_list);

    mGtk = rb_define_module("Gtk");

    gObject = rb_define_class_under(mGtk, "GtkObject", cObject);
    gWidget = rb_define_class_under(mGtk, "Widget", gObject);
    gContainer = rb_define_class_under(mGtk, "Container", gWidget);
    gBin = rb_define_class_under(mGtk, "Bin", gContainer);
    gAlignment = rb_define_class_under(mGtk, "Alignment", gBin);
    gMisc = rb_define_class_under(mGtk, "Misc", gWidget);
    gArrow = rb_define_class_under(mGtk, "Arrow", gMisc);
    gFrame = rb_define_class_under(mGtk, "Frame", gBin);
    gAspectFrame = rb_define_class_under(mGtk, "AspectFrame", gFrame);
    gData = rb_define_class_under(mGtk, "Data", gObject);
    gAdjustment = rb_define_class_under(mGtk, "Adjustment", gData);
    gBox = rb_define_class_under(mGtk, "Box", gContainer);
    gButton = rb_define_class_under(mGtk, "Button", gContainer);
    gTButton = rb_define_class_under(mGtk, "ToggleButton", gButton);
    gCButton = rb_define_class_under(mGtk, "CheckButton", gTButton);
    gRButton = rb_define_class_under(mGtk, "RadioButton", gCButton);
    gBBox = rb_define_class_under(mGtk, "ButtonBox", gBox);
    gCList = rb_define_class_under(mGtk, "CList", gContainer);
    gWindow = rb_define_class_under(mGtk, "Window", gBin);
    gDialog = rb_define_class_under(mGtk, "Dialog", gWindow);
    gFileSel = rb_define_class_under(mGtk, "FileSelection", gWindow);
    gVBox = rb_define_class_under(mGtk, "VBox", gBox);
    gColorSel = rb_define_class_under(mGtk, "ColorSelection", gVBox);
    gColorSelDialog = rb_define_class_under(mGtk, "ColorSelectionDialog", gWindow);
    gImage = rb_define_class_under(mGtk, "Image", gMisc);
    gDrawArea = rb_define_class_under(mGtk, "DrawingArea", gWidget);
    gEntry = rb_define_class_under(mGtk, "Entry", gWidget);
    gEventBox = rb_define_class_under(mGtk, "EventBox", gBin);
    gFixed = rb_define_class_under(mGtk, "Fixed", gContainer);
    gGamma = rb_define_class_under(mGtk, "GammaCurve", gVBox);
    gHBBox = rb_define_class_under(mGtk, "HButtonBox", gBBox);
    gVBBox = rb_define_class_under(mGtk, "VButtonBox", gBBox);
    gHBox = rb_define_class_under(mGtk, "HBox", gBox);
    gPaned = rb_define_class_under(mGtk, "Paned", gContainer);
    gHPaned = rb_define_class_under(mGtk, "HPaned", gPaned);
    gVPaned = rb_define_class_under(mGtk, "VPaned", gPaned);
    gRuler = rb_define_class_under(mGtk, "Ruler", gWidget);
    gHRuler = rb_define_class_under(mGtk, "HRuler", gRuler);
    gVRuler = rb_define_class_under(mGtk, "VRuler", gRuler);
    gRange = rb_define_class_under(mGtk, "Range", gWidget);
    gScale = rb_define_class_under(mGtk, "Scale", gRange);
    gHScale = rb_define_class_under(mGtk, "HScale", gScale);
    gVScale = rb_define_class_under(mGtk, "VScale", gScale);
    gScrollbar = rb_define_class_under(mGtk, "Scrollbar", gRange);
    gHScrollbar = rb_define_class_under(mGtk, "HScrollbar", gScrollbar);
    gVScrollbar = rb_define_class_under(mGtk, "VScrollbar", gScrollbar);
    gSeparator = rb_define_class_under(mGtk, "Separator", gWidget);
    gHSeparator = rb_define_class_under(mGtk, "HSeparator", gSeparator);
    gVSeparator = rb_define_class_under(mGtk, "VSeparator", gSeparator);
    gInputDialog = rb_define_class_under(mGtk, "InputDialog", gDialog);
    gLabel = rb_define_class_under(mGtk, "Label", gMisc);
    gList = rb_define_class_under(mGtk, "List", gContainer);
    gItem = rb_define_class_under(mGtk, "Item", gBin);
    gListItem = rb_define_class_under(mGtk, "ListItem", gItem);
    gMenuShell = rb_define_class_under(mGtk, "MenuShell", gContainer);
    gMenu = rb_define_class_under(mGtk, "Menu", gMenuShell);
    gMenuBar = rb_define_class_under(mGtk, "MenuBar", gMenuShell);
    gMenuItem = rb_define_class_under(mGtk, "MenuItem", gItem);
    gCMenuItem = rb_define_class_under(mGtk, "CheckMenuItem", gMenuItem);
    gRMenuItem = rb_define_class_under(mGtk, "RadioMenuItem", gCMenuItem);
    gNotebook = rb_define_class_under(mGtk, "Notebook", gContainer);
    gOptionMenu = rb_define_class_under(mGtk, "OptionMenu", gButton);
    gPixmap = rb_define_class_under(mGtk, "Pixmap", gMisc);
    gPreview = rb_define_class_under(mGtk, "Preview", gWidget);
    gProgressBar = rb_define_class_under(mGtk, "ProgressBar", gWidget);
    gScrolledWin = rb_define_class_under(mGtk, "ScrolledWindow", gContainer);
    gTable = rb_define_class_under(mGtk, "Table", gContainer);
    gText = rb_define_class_under(mGtk, "Text", gWidget);
    gToolbar = rb_define_class_under(mGtk, "Toolbar", gContainer);
    gTooltips = rb_define_class_under(mGtk, "Tooltips", cObject);
    gTree = rb_define_class_under(mGtk, "Tree", gContainer);
    gTreeItem = rb_define_class_under(mGtk, "TreeItem", gItem);
    gViewPort = rb_define_class_under(mGtk, "ViewPort", gBin);

    gAcceleratorTable = rb_define_class_under(mGtk, "AcceleratorTable", cObject);
    gStyle = rb_define_class_under(mGtk, "Style", cObject);
    gPreviewInfo = rb_define_class_under(mGtk, "PreviewInfo", cObject);
    gRequisiton = rb_define_class_under(mGtk, "Requisiton", cObject);
    gAllocation = rb_define_class_under(mGtk, "Allocation", cObject);

    mGdk = rb_define_module("Gdk");

    gdkFont = rb_define_class_under(mGdk, "Font", cObject);
    gdkColor = rb_define_class_under(mGdk, "Color", cObject);
    gdkPixmap = rb_define_class_under(mGdk, "Pixmap", cObject);
    gdkBitmap = rb_define_class_under(mGdk, "Bitmap", gdkPixmap);
    gdkWindow = rb_define_class_under(mGdk, "Window", cObject);
    gdkImage = rb_define_class_under(mGdk, "Image", cObject);
    gdkVisual = rb_define_class_under(mGdk, "Visual", cObject);
    gdkGC = rb_define_class_under(mGdk, "GC", cObject);
    gdkGCValues = rb_define_class_under(mGdk, "GCValues", cObject);
    gdkRectangle = rb_define_class_under(mGdk, "Rectangle", cObject);
    gdkSegment = rb_define_class_under(mGdk, "Segment", cObject);
    gdkWindowAttr = rb_define_class_under(mGdk, "WindowAttr", cObject);
    gdkCursor = rb_define_class_under(mGdk, "Cursor", cObject);
    gdkAtom = rb_define_class_under(mGdk, "Atom", cObject);
    gdkColorContext = rb_define_class_under(mGdk, "ColotContext", cObject);
    gdkEvent = rb_define_class_under(mGdk, "gdkEvent", cObject);

    /* GtkObject */
    rb_define_method(gObject, "initialize", gobj_initialize, -1);
    rb_define_method(gObject, "set_flags", gobj_set_flags, 1);
    rb_define_method(gObject, "unset_flags", gobj_unset_flags, 1);
    rb_define_method(gObject, "destroy", gobj_destroy, 0);
    rb_define_method(gObject, "signal_connect", gobj_sig_connect, -1);
    rb_define_method(gObject, "signal_connect_after", gobj_sig_connect_after, -1);
    rb_define_method(gObject, "singleton_method_added", gobj_smethod_added, 1);

    /* Widget */
    rb_define_method(gWidget, "destroy", widget_destroy, 0);
    rb_define_method(gWidget, "show", widget_show, 0);
    rb_define_method(gWidget, "show_all", widget_show_all, 0);
    rb_define_method(gWidget, "hide", widget_hide, 0);
    rb_define_method(gWidget, "hide_all", widget_hide_all, 0);
    rb_define_method(gWidget, "map", widget_map, 0);
    rb_define_method(gWidget, "unmap", widget_unmap, 0);
    rb_define_method(gWidget, "realize", widget_realize, 0);
    rb_define_method(gWidget, "unrealize", widget_unrealize, 0);
    rb_define_method(gWidget, "queue_draw", widget_queue_draw, 0);
    rb_define_method(gWidget, "queue_resize", widget_queue_resize, 0);
    rb_define_method(gWidget, "draw", widget_draw, 1);
    rb_define_method(gWidget, "draw_focus", widget_draw_focus, 0);
    rb_define_method(gWidget, "draw_default", widget_draw_default, 0);
    rb_define_method(gWidget, "draw_children", widget_draw_children, 0);
    rb_define_method(gWidget, "size_request", widget_size_request, 1);
    rb_define_method(gWidget, "size_alocate", widget_size_allocate, 1);
    rb_define_method(gWidget, "install_accelerator", widget_inst_accel, 4);
    rb_define_method(gWidget, "remove_accelerator", widget_rm_accel, 4);
    rb_define_method(gWidget, "event", widget_event, 1);
    rb_define_method(gWidget, "activate", widget_activate, 0);
    rb_define_method(gWidget, "grab_focus", widget_grab_focus, 0);
    rb_define_method(gWidget, "grab_default", widget_grab_default, 0);
    rb_define_method(gWidget, "restore_state", widget_restore_state, 0);
    rb_define_method(gWidget, "visible?", widget_visible, 0);
    rb_define_method(gWidget, "reparent", widget_reparent, 1);
    rb_define_method(gWidget, "popup", widget_popup, 2);
    rb_define_method(gWidget, "intersect", widget_intersect, 2);
    rb_define_method(gWidget, "basic", widget_basic, 0);
    rb_define_method(gWidget, "get_name", widget_set_name, 0);
    rb_define_method(gWidget, "set_name", widget_set_name, 1);
    rb_define_method(gWidget, "set_parent", widget_set_parent, 1);
    rb_define_method(gWidget, "set_sensitive", widget_set_sensitive, 1);
    rb_define_method(gWidget, "set_usize", widget_set_usize, 2);
    rb_define_method(gWidget, "set_uposition", widget_set_uposition, 2);
    rb_define_method(gWidget, "set_style", widget_set_style, 1);
    rb_define_method(gWidget, "set_events", widget_set_events, 1);
    rb_define_method(gWidget, "set_extension_events", widget_set_eevents, 1);
    rb_define_method(gWidget, "unparent", widget_unparent, 0);
    rb_define_method(gWidget, "get_toplevel", widget_get_toplevel, 0);
    rb_define_method(gWidget, "get_ancestor", widget_get_ancestor, 1);
    rb_define_method(gWidget, "get_colormap", widget_get_colormap, 0);
    rb_define_method(gWidget, "get_visual", widget_get_visual, 0);
    rb_define_method(gWidget, "get_style", widget_get_style, 0);
    rb_define_method(gWidget, "style", widget_get_style, 0);
    rb_define_method(gWidget, "get_events", widget_get_events, 0);
    rb_define_method(gWidget, "get_extension_events", widget_get_eevents, 0);
    rb_define_method(gWidget, "get_pointer", widget_get_eevents, 0);
    rb_define_method(gWidget, "ancestor?", widget_is_ancestor, 1);
    rb_define_method(gWidget, "child?", widget_is_child, 1);
    rb_define_method(gWidget, "window", widget_window, 0);

    rb_define_singleton_method(gWidget, "push_colomap", widget_push_cmap, 1);
    rb_define_singleton_method(gWidget, "push_visual", widget_push_visual, 1);
    rb_define_singleton_method(gWidget, "push_style", widget_push_style, 1);
    rb_define_singleton_method(gWidget, "pop_colomap", widget_pop_cmap, 0);
    rb_define_singleton_method(gWidget, "pop_visual", widget_pop_visual, 0);
    rb_define_singleton_method(gWidget, "pop_style", widget_pop_style, 0);

    rb_define_singleton_method(gWidget, "set_default_colomap",
			       widget_set_default_cmap, 1);
    rb_define_singleton_method(gWidget, "set_default_visual",
			       widget_set_default_visual, 1);
    rb_define_singleton_method(gWidget, "set_default_style",
			       widget_set_default_style, 1);
    rb_define_singleton_method(gWidget, "get_default_colomap",
			       widget_get_default_cmap, 0);
    rb_define_singleton_method(gWidget, "get_default_visual",
			       widget_get_default_visual, 0);
    rb_define_singleton_method(gWidget, "get_default_style",
			       widget_get_default_style, 0);
    rb_define_singleton_method(gWidget, "set_default_colomap",
			       widget_set_default_cmap, 1);
    rb_define_singleton_method(gWidget, "set_default_visual",
			       widget_set_default_visual, 1);
    rb_define_singleton_method(gWidget, "set_default_style",
			       widget_set_default_style, 1);
    rb_define_singleton_method(gWidget, "set_default_colomap",
			       widget_set_default_cmap, 1);
    rb_define_singleton_method(gWidget, "set_default_visual",
			       widget_set_default_visual, 1);
    rb_define_singleton_method(gWidget, "propagage_default_style",
			       widget_propagate_default_style, 0);

    /* Container */
    rb_define_method(gContainer, "border_width", cont_bwidth, 1);
    rb_define_method(gContainer, "add", cont_add, 1);
    rb_define_method(gContainer, "disable_resize", cont_disable_resize, 0);
    rb_define_method(gContainer, "enable_resize", cont_enable_resize, 0);
    rb_define_method(gContainer, "block_resize", cont_block_resize, 0);
    rb_define_method(gContainer, "unblock_resize", cont_unblock_resize, 0);
    rb_define_method(gContainer, "need_resize", cont_need_resize, 0);
    rb_define_method(gContainer, "foreach", cont_foreach, -1);
    rb_define_method(gContainer, "each", cont_each, 0);
    rb_define_method(gContainer, "focus", cont_focus, 1);
    rb_define_method(gContainer, "children", cont_children, 0);

    /* Bin */
    /* -- */

    /* Alignment */
    rb_define_method(gAlignment, "initialize", align_initialize, 4);
    rb_define_method(gAlignment, "set", align_set, 4);

    /* Misc */
    rb_define_method(gMisc, "set_alignment", misc_set_align, 2);
    rb_define_method(gMisc, "set_padding", misc_set_padding, 2);
    
    /* Arrow */
    rb_define_method(gArrow, "initialize", arrow_initialize, 2);
    rb_define_method(gArrow, "set", arrow_initialize, 2);

    /* Frame */
    rb_define_method(gFrame, "initialize", frame_initialize, 1);
    rb_define_method(gFrame, "set_label", frame_set_label, 1);
    rb_define_method(gFrame, "set_label_align", frame_set_label_align, 2);
    rb_define_method(gFrame, "set_shadow_type", frame_set_shadow_type, 1);

    /* AspectFrame */
    rb_define_method(gAspectFrame, "initialize", aframe_initialize, 5);
    rb_define_method(gAspectFrame, "set", aframe_set, 4);

    /* Data */
    /* -- */

    /* Adjustment */
    rb_define_method(gAdjustment, "initialize", adj_initialize, 6);

    /* Box */
    rb_define_method(gBox, "pack_start", box_pack_start, -1);
    rb_define_method(gBox, "pack_end", box_pack_end, -1);

    /* Button */
    rb_define_method(gButton, "initialize", button_initialize, -1);
    rb_define_method(gButton, "pressed", button_pressed, 0);
    rb_define_method(gButton, "released", button_released, 0);
    rb_define_method(gButton, "clicked", button_clicked, 0);
    rb_define_method(gButton, "enter", button_enter, 0);
    rb_define_method(gButton, "leave", button_leave, 0);

    /* ToggleButton */
    rb_define_method(gTButton, "initialize", tbtn_initialize, -1);
    rb_define_method(gTButton, "set_mode", tbtn_set_mode, 1);
    rb_define_method(gTButton, "set_state", tbtn_set_state, 1);
    rb_define_method(gTButton, "toggled", tbtn_toggled, 0);

    /* CheckButton */
    rb_define_method(gCButton, "initialize", cbtn_initialize, -1);

    /* RadioButton */
    rb_define_method(gCButton, "initialize", rbtn_initialize, -1);
    rb_define_method(gCButton, "group", rbtn_group, 0);

    /* ButtonBox */
    rb_define_singleton_method(gBBox, "get_child_size_default",
			       bbox_get_child_size_default, 0);
    rb_define_singleton_method(gBBox, "get_child_ipadding_default",
			       bbox_get_child_ipadding_default, 0);
    rb_define_singleton_method(gBBox, "set_child_size_default",
			       bbox_set_child_size_default, 2);
    rb_define_singleton_method(gBBox, "set_child_ipadding_default",
			       bbox_set_child_ipadding_default, 2);
    rb_define_method(gBBox, "get_spacing", bbox_get_spacing, 0);
    rb_define_method(gBBox, "get_layout", bbox_get_layout, 0);
    rb_define_method(gBBox, "get_child_size", bbox_get_child_size, 0);
    rb_define_method(gBBox, "get_child_ipadding", bbox_get_child_ipadding, 0);
    rb_define_method(gBBox, "set_spacing", bbox_set_spacing, 1);
    rb_define_method(gBBox, "set_layout", bbox_set_layout, 1);
    rb_define_method(gBBox, "set_child_size", bbox_set_child_size, 2);
    rb_define_method(gBBox, "set_child_ipadding", bbox_set_child_ipadding, 2);

    /* CList */
    rb_define_method(gCList, "initialize", clist_initialize, -1);
    rb_define_method(gCList, "set_border", clist_set_border, 1);
    rb_define_method(gCList, "set_selection_mode", clist_set_sel_mode, 1);
    rb_define_method(gCList, "set_policy", clist_set_policy, 2);
    rb_define_method(gCList, "freeze", clist_freeze, 0);
    rb_define_method(gCList, "thaw", clist_thaw, 0);
    rb_define_method(gCList, "column_titles_show", clist_col_titles_show, 0);
    rb_define_method(gCList, "column_titles_hide", clist_col_titles_hide, 0);
    rb_define_method(gCList, "column_title_active", clist_col_title_active, 1);
    rb_define_method(gCList, "column_title_passive", clist_col_title_passive, 1);
    rb_define_method(gCList, "column_titles_active", clist_col_title_active, 0);
    rb_define_method(gCList, "column_titles_passive", clist_col_title_passive, 0);
    rb_define_method(gCList, "set_column_title", clist_set_col_title, 2);
    rb_define_method(gCList, "set_column_widget", clist_set_col_wigdet, 2);
    rb_define_method(gCList, "set_column_justification", clist_set_col_just, 2);
    rb_define_method(gCList, "set_column_width", clist_set_col_width, 2);
    rb_define_method(gCList, "set_row_height", clist_set_row_height, 1);
    rb_define_method(gCList, "moveto", clist_moveto, 4);
    rb_define_method(gCList, "set_text", clist_set_text, 3);
    rb_define_method(gCList, "set_pixmap", clist_set_text, 4);
    rb_define_method(gCList, "set_pixtext", clist_set_pixtext, 6);
    rb_define_method(gCList, "set_foreground", clist_set_foreground, 2);
    rb_define_method(gCList, "set_background", clist_set_background, 2);
    rb_define_method(gCList, "set_shift", clist_set_shift, 4);
    rb_define_method(gCList, "append", clist_append, 1);
    rb_define_method(gCList, "insert", clist_insert, 2);
    rb_define_method(gCList, "remove", clist_remove, 1);
    rb_define_method(gCList, "set_row_data", clist_set_row_data, 2);
    rb_define_method(gCList, "get_row_data", clist_set_row_data, 1);
    rb_define_method(gCList, "select_row", clist_select_row, 2);
    rb_define_method(gCList, "unselect_row", clist_unselect_row, 2);
    rb_define_method(gCList, "clear", clist_clear, 0);

    /* Window */
    rb_define_method(gWindow, "initialize", gwin_initialize, 1);
    rb_define_method(gWindow, "set_title", gwin_set_title, 1);
    rb_define_method(gWindow, "set_policy", gwin_set_policy, 3);
    rb_define_method(gWindow, "set_wmclass", gwin_set_wmclass, 1);
    rb_define_method(gWindow, "set_focus", gwin_set_focus, 1);
    rb_define_method(gWindow, "set_default", gwin_set_focus, 1);
    rb_define_method(gWindow, "add_accelerator_table", gwin_add_accel, 1);
    rb_define_method(gWindow, "remove_accelerator_table", gwin_rm_accel, 1);
    rb_define_method(gWindow, "position", gwin_position, 1);

    /* Dialog */
    rb_define_method(gDialog, "initialize", dialog_initialize, 0);

    /* FileSelection */
    rb_define_method(gFileSel, "initialize", fsel_initialize, 1);
    rb_define_method(gFileSel, "set_filename", fsel_set_fname, 1);
    rb_define_method(gFileSel, "get_filename", fsel_get_fname, 0);
    rb_define_method(gFileSel, "ok_button", fsel_ok_button, 0);
    rb_define_method(gFileSel, "cancel_button", fsel_cancel_button, 0);
    rb_define_method(gFileSel, "help_button", fsel_help_button, 0);

    /* VBox */
    rb_define_method(gVBox, "initialize", vbox_initialize, -1);

    /* ColorSelection */
    rb_define_method(gColorSel, "initialize", colorsel_initialize, 0);
    rb_define_method(gColorSel, "set_update_policy", colorsel_set_update_policy, 1);
    rb_define_method(gColorSel, "set_opacity", colorsel_set_opacity, 1);
    rb_define_method(gColorSel, "set_color", colorsel_set_color, 1);
    rb_define_method(gColorSel, "get_color", colorsel_get_color, 0);

    /* ColorSelectionDialog */
    rb_define_method(gColorSelDialog, "initialize", cdialog_initialize, 1);

    /* Image */
    rb_define_method(gImage, "initialize", image_initialize, 2);
    rb_define_method(gImage, "set", image_set, 2);
    rb_define_method(gImage, "get", image_get, 0);

    /* DrawingArea */
    rb_define_method(gDrawArea, "initialize", darea_initialize, 0);
    rb_define_method(gDrawArea, "size", darea_size, 2);

    /* Entry */
    rb_define_method(gEntry, "initialize", entry_initialize, 0);
    rb_define_method(gEntry, "set_text", entry_set_text, 1);

    /* EventBox */
    rb_define_method(gEventBox, "initialize", eventbox_initialize, 0);

    /* Fixed */
    rb_define_method(gFixed, "initialize", fixed_initialize, 0);
    rb_define_method(gFixed, "put", fixed_put, 3);
    rb_define_method(gFixed, "move", fixed_move, 3);

    /* GammaCurve */
    rb_define_method(gGamma, "initialize", gamma_initialize, 0);
    rb_define_method(gGamma, "gamma", gamma_gamma, 0);
    
    /* HButtonBox */
    rb_define_method(gHBBox, "initialize", hbbox_initialize, 0);
    rb_define_singleton_method(gHBBox, "get_spacing_default",
			       hbbox_get_spacing_default, 0);
    rb_define_singleton_method(gHBBox, "get_layout_default",
			       hbbox_get_spacing_default, 0);
    rb_define_singleton_method(gHBBox, "set_spacing_default",
			       hbbox_set_spacing_default, 1);
    rb_define_singleton_method(gHBBox, "set_layout_default",
			       hbbox_set_layout_default, 1);

    /* VButtonBox */
    rb_define_method(gVBBox, "initialize", vbbox_initialize, 0);
    rb_define_singleton_method(gVBBox, "get_spacing_default",
			       vbbox_get_spacing_default, 0);
    rb_define_singleton_method(gVBBox, "get_layout_default",
			       vbbox_get_spacing_default, 0);
    rb_define_singleton_method(gVBBox, "set_spacing_default",
			       vbbox_set_spacing_default, 1);
    rb_define_singleton_method(gVBBox, "set_layout_default",
			       vbbox_set_layout_default, 1);

    /* HBox */
    rb_define_method(gHBox, "initialize", hbox_initialize, -1);

    /* Paned */
    rb_define_method(gPaned, "add1", paned_add1, 1);
    rb_define_method(gPaned, "add2", paned_add1, 1);
    rb_define_method(gPaned, "handle_size", paned_handle_size, 1);
    rb_define_method(gPaned, "gutter_size", paned_gutter_size, 1);

    /* HPaned */
    rb_define_method(gHPaned, "initialize", hpaned_initialize, 0);

    /* VPaned */
    rb_define_method(gVPaned, "initialize", vpaned_initialize, 0);

    /* Ruler */
    rb_define_method(gRuler, "set_metric", ruler_set_metric, 1);
    rb_define_method(gRuler, "set_range", ruler_set_range, 4);
    rb_define_method(gRuler, "draw_ticks", ruler_draw_ticks, 0);
    rb_define_method(gRuler, "draw_pos", ruler_draw_pos, 0);

    /* HRuler */
    rb_define_method(gHRuler, "initialize", hruler_initialize, 0);

    /* VRuler */
    rb_define_method(gVRuler, "initialize", vruler_initialize, 0);

    /* Range */
    rb_define_method(gRange, "get_adjustment", range_get_adj, 0);
    rb_define_method(gRange, "set_update_policy", range_set_update_policy, 1);
    rb_define_method(gRange, "set_adjustment", range_set_adj, 1);
    rb_define_method(gRange, "draw_background", range_draw_bg, 0);
    rb_define_method(gRange, "draw_trough", range_draw_trough, 0);
    rb_define_method(gRange, "draw_slider", range_draw_slider, 0);
    rb_define_method(gRange, "draw_step_forw", range_draw_step_forw, 0);
    rb_define_method(gRange, "draw_step_back", range_draw_step_back, 0);
    rb_define_method(gRange, "slider_update", range_slider_update, 0);
    rb_define_method(gRange, "trough_click", range_trough_click, 2);
    rb_define_method(gRange, "draw_background", range_draw_bg, 2);
    rb_define_method(gRange, "default_hslider_update", range_default_hslider_update, 0);
    rb_define_method(gRange, "default_vslider_update", range_default_vslider_update, 0);
    rb_define_method(gRange, "default_htrough_click", range_default_htrough_click, 2);
    rb_define_method(gRange, "default_vtrough_click", range_default_vtrough_click, 2);
    rb_define_method(gRange, "default_hmotion", range_default_hmotion, 2);
    rb_define_method(gRange, "default_vmotion", range_default_vmotion, 2);
    rb_define_method(gRange, "calc_value", range_calc_value, 1);

    /* Scale */
    rb_define_method(gScale, "set_digits", scale_set_digits, 1);
    rb_define_method(gScale, "set_draw_value", scale_set_draw_value, 1);
    rb_define_method(gScale, "set_value_pos", scale_set_value_pos, 1);
    rb_define_method(gScale, "value_width", scale_value_width, 0);
    rb_define_method(gScale, "draw_value", scale_draw_value, 0);

    /* HScale */
    rb_define_method(gHScale, "initialize", hscale_initialize, -1);

    /* VScale */
    rb_define_method(gVScale, "initialize", vscale_initialize, -1);

    /* Scrollbar */
    /* -- */

    /* HScrollbar */
    rb_define_method(gHScrollbar, "initialize", hscrollbar_initialize, -1);

    /* VScrollbar */
    rb_define_method(gVScrollbar, "initialize", vscrollbar_initialize, -1);

    /* Separator */
    /* -- */

    /* HSeparator */
    rb_define_method(gHSeparator, "initialize", hsep_initialize, 0);

    /* VSeparator */
    rb_define_method(gVSeparator, "initialize", vsep_initialize, 0);

    /* InputDialog */
    rb_define_method(gInputDialog, "initialize", idiag_initialize, 0);

    /* Label */
    rb_define_method(gLabel, "initialize", label_initialize, 1);

    /* List */
    rb_define_method(gList, "initialize", list_initialize, 0);
    rb_define_method(gList, "set_selection_mode", list_set_sel_mode, 1);
    rb_define_method(gList, "selection_mode", list_sel_mode, 1);
    rb_define_method(gList, "selection", list_selection, 0);
    rb_define_method(gList, "insert_items", list_insert_items, 2);
    rb_define_method(gList, "append_items", list_append_items, 1);
    rb_define_method(gList, "prepend_items", list_prepend_items, 1);
    rb_define_method(gList, "remove_items", list_remove_items, 1);
    rb_define_method(gList, "clear_items", list_clear_items, 2);
    rb_define_method(gList, "select_item", list_select_item, 1);
    rb_define_method(gList, "unselect_item", list_unselect_item, 1);
    rb_define_method(gList, "select_child", list_select_child, 1);
    rb_define_method(gList, "unselect_child", list_unselect_child, 1);
    rb_define_method(gList, "child_position", list_child_position, 1);

    /* Item */
    rb_define_method(gItem, "select", item_select, 0);
    rb_define_method(gItem, "deselect", item_deselect, 0);
    rb_define_method(gItem, "toggle", item_toggle, 0);

    /* ListItem */
    rb_define_method(gListItem, "initialize", litem_initialize, -1);

    /* MenuShell */
    rb_define_method(gMenuShell, "append", mshell_append, 1);
    rb_define_method(gMenuShell, "prepend", mshell_prepend, 1);
    rb_define_method(gMenuShell, "insert", mshell_insert, 2);
    rb_define_method(gMenuShell, "deactivate", mshell_deactivate, 0);

    /* Menu */
    rb_define_method(gMenu, "initialize", menu_initialize, 0);
    rb_define_method(gMenu, "append", menu_append, 1);
    rb_define_method(gMenu, "prepend", menu_prepend, 1);
    rb_define_method(gMenu, "insert", menu_insert, 2);
    rb_define_method(gMenu, "popup", menu_popup, 6);
    rb_define_method(gMenu, "popdown", menu_popup, 0);
    rb_define_method(gMenu, "get_active", menu_get_active, 0);
    rb_define_method(gMenu, "set_active", menu_set_active, 1);
    rb_define_method(gMenu, "set_accelerator_table", menu_set_acceltbl, 1);

    /* MenuBar */
    rb_define_method(gMenuBar, "initialize", mbar_initialize, 0);
    rb_define_method(gMenuBar, "append", mbar_append, 1);
    rb_define_method(gMenuBar, "prepend", mbar_prepend, 1);
    rb_define_method(gMenuBar, "insert", mbar_insert, 2);

    /* MenuItem */
    rb_define_method(gMenuItem, "initialize", mitem_initialize, -1);
    rb_define_method(gMenuItem, "set_submenu", mitem_set_submenu, 1);
    rb_define_method(gMenuItem, "set_placement", mitem_set_placement, 1);
    rb_define_method(gMenuItem, "accelerator_size", mitem_accelerator_size, 0);
    rb_define_method(gMenuItem, "accelerator_text", mitem_accelerator_text, 0);
    rb_define_method(gMenuItem, "configure", mitem_configure, 2);
    rb_define_method(gMenuItem, "select", mitem_select, 0);
    rb_define_method(gMenuItem, "deselect", mitem_deselect, 0);
    rb_define_method(gMenuItem, "activate", mitem_activate, 0);
    rb_define_method(gMenuItem, "right_justify", mitem_right_justify, 0);

    /* CheckMenuItem */
    rb_define_method(gCMenuItem, "initialize", cmitem_initialize, -1);
    rb_define_method(gCMenuItem, "set_state", cmitem_set_state, 1);
    rb_define_method(gCMenuItem, "set_show_toggle", cmitem_set_show_toggle, 1);
    rb_define_method(gCMenuItem, "toggled", cmitem_toggled, 0);

    /* RadioMenuItem */
    rb_define_method(gRMenuItem, "initialize", rmitem_initialize, -1);
    rb_define_method(gRMenuItem, "group", rmitem_group, 0);

    /* NoteBook */
    rb_define_method(gNotebook, "initialize", note_initialize, 0);
    rb_define_method(gNotebook, "append_page", note_append_page, 2);
    rb_define_method(gNotebook, "prepend_page", note_prepend_page, 2);
    rb_define_method(gNotebook, "insert_page", note_insert_page, 3);
    rb_define_method(gNotebook, "remove_page", note_remove_page, 1);
    rb_define_method(gNotebook, "set_page", note_set_page, 1);
    rb_define_method(gNotebook, "cur_page", note_cur_page, 0);
    rb_define_method(gNotebook, "page", note_cur_page, 0);
    rb_define_method(gNotebook, "next_page", note_next_page, 0);
    rb_define_method(gNotebook, "prev_page", note_prev_page, 0);
    rb_define_method(gNotebook, "set_tab_pos", note_set_tab_pos, 1);
    rb_define_method(gNotebook, "tab_pos", note_tab_pos, 0);
    rb_define_method(gNotebook, "set_show_tabs", note_set_show_tabs, 1);
    rb_define_method(gNotebook, "show_tabs", note_show_tabs, 0);
    rb_define_method(gNotebook, "set_show_border", note_set_show_border, 1);
    rb_define_method(gNotebook, "show_border", note_show_border, 0);

    /* OptionMenu */
    rb_define_method(gOptionMenu, "initialize", omenu_initialize, 0);
    rb_define_method(gOptionMenu, "get_menu", omenu_get_menu, 0);
    rb_define_method(gOptionMenu, "set_menu", omenu_set_menu, 1);
    rb_define_method(gOptionMenu, "remove_menu", omenu_set_menu, 0);
    rb_define_method(gOptionMenu, "set_history", omenu_set_history, 1);

    /* Pixmap */
    rb_define_method(gPixmap, "initialize", pixmap_initialize, 2);
    rb_define_method(gPixmap, "set", pixmap_set, 2);
    rb_define_method(gPixmap, "get", pixmap_get, 0);

    /* Preview */
    rb_define_method(gPreview, "initialize", preview_initialize, 1);
    rb_define_method(gPreview, "size", preview_size, 2);
    rb_define_method(gPreview, "put", preview_size, 8);
    rb_define_method(gPreview, "put_row", preview_size, 5);
    rb_define_method(gPreview, "draw_row", preview_size, 4);
    rb_define_method(gPreview, "set_expand", preview_set_expand, 1);
    rb_define_singleton_method(gPreview, "set_gamma", preview_set_gamma, 1);
    rb_define_singleton_method(gPreview, "set_color_cube",
			       preview_set_color_cube, 4);
    rb_define_singleton_method(gPreview, "set_install_cmap",
			       preview_set_install_cmap, 1);
    rb_define_singleton_method(gPreview, "set_reserved",
			       preview_set_reserved, 1);
    rb_define_singleton_method(gPreview, "get_visual", preview_get_visual, 0);
    rb_define_singleton_method(gPreview, "get_cmap", preview_get_cmap, 0);
    rb_define_singleton_method(gPreview, "get_info", preview_get_info, 0);

    /* ProgressBar */
    rb_define_method(gProgressBar, "initialize", pbar_initialize, 0);
    rb_define_method(gProgressBar, "update", pbar_update, 1);

    /* ScrolledWindow */
    rb_define_method(gScrolledWin, "initialize", scwin_initialize, -1);
    rb_define_method(gScrolledWin, "set_policy", scwin_set_policy, 2);

    /* Table */
    rb_define_method(gTable, "initialize", tbl_initialize, -1);
    rb_define_method(gTable, "attach", tbl_attach, -1);
    rb_define_method(gTable, "set_row_spacing", tbl_set_row_spacing, 2);
    rb_define_method(gTable, "set_col_spacing", tbl_set_col_spacing, 2);
    rb_define_method(gTable, "set_row_spacings", tbl_set_row_spacings, 1);
    rb_define_method(gTable, "set_col_spacings", tbl_set_col_spacings, 1);

    /* Text */
    rb_define_method(gText, "initialize", txt_initialize, -1);
    rb_define_method(gText, "set_editable", txt_set_editable, 1);
    rb_define_method(gText, "set_adjustment", txt_set_adjustment, 2);
    rb_define_method(gText, "set_point", txt_set_point, 1);
    rb_define_method(gText, "get_point", txt_get_point, 0);
    rb_define_method(gText, "get_length", txt_get_length, 0);
    rb_define_method(gText, "freeze", txt_freeze, 0);
    rb_define_method(gText, "thaw", txt_thaw, 0);
    rb_define_method(gText, "insert", txt_insert, 4);
    rb_define_method(gText, "backward_delete", txt_backward_delete, 1);
    rb_define_method(gText, "forward_delete", txt_forward_delete, 1);

    /* Toolbar */
    rb_define_method(gToolbar, "initialize", tbar_initialize, -1);
    rb_define_method(gToolbar, "append_item", tbar_append_item, 4);
    rb_define_method(gToolbar, "prepend_item", tbar_prepend_item, 4);
    rb_define_method(gToolbar, "insert_item", tbar_append_item, 5);
    rb_define_method(gToolbar, "append_space", tbar_append_space, 0);
    rb_define_method(gToolbar, "prepend_space", tbar_prepend_space, 0);
    rb_define_method(gToolbar, "insert_space", tbar_append_space, 1);
    rb_define_method(gToolbar, "set_orientation", tbar_set_orientation, 1);
    rb_define_method(gToolbar, "set_style", tbar_set_style, 1);
    rb_define_method(gToolbar, "set_space_size", tbar_set_space_size, 1);
    rb_define_method(gToolbar, "set_tooltips", tbar_set_tooltips, 1);

    /* Tooltips */
    rb_define_method(gTooltips, "initialize", ttips_initialize, 0);
    rb_define_method(gTooltips, "set_tips", ttips_set_tips, 2);
    rb_define_method(gTooltips, "set_delay", ttips_set_delay, 1);
    rb_define_method(gTooltips, "enable", ttips_enable, 0);
    rb_define_method(gTooltips, "disable", ttips_disable, 0);

    /* Tree */
    rb_define_method(gTree, "initialize", tree_initialize, 0);
    rb_define_method(gTree, "append", tree_append, 1);
    rb_define_method(gTree, "prepend", tree_prepend, 1);
    rb_define_method(gTree, "insert", tree_insert, 2);

    /* TreeItem */
    rb_define_method(gTreeItem, "initialize", titem_initialize, -1);
    rb_define_method(gTreeItem, "set_subtree", titem_set_subtree, 1);
    rb_define_method(gTreeItem, "select", titem_select, 0);
    rb_define_method(gTreeItem, "deselect", titem_deselect, 0);
    rb_define_method(gTreeItem, "expand", titem_expand, 0);
    rb_define_method(gTreeItem, "collapse", titem_collapse, 0);

    /* ViewPort */
    rb_define_method(gViewPort, "initialize", vport_initialize, -1);
    rb_define_method(gViewPort, "get_hadjustment", vport_get_hadj, 0);
    rb_define_method(gViewPort, "get_vadjustment", vport_get_vadj, 0);
    rb_define_method(gViewPort, "set_hadjustment", vport_set_hadj, 1);
    rb_define_method(gViewPort, "set_vadjustment", vport_set_vadj, 1);
    rb_define_method(gViewPort, "set_shadow_type", vport_set_shadow, 1);

    /* AcceleratorTable */
    /* Style */

    /* Gtk module */
    rb_define_module_function(mGtk, "main", gtk_m_main, 0);
    rb_define_module_function(mGtk, "timeout_add", timeout_add, -1);
    rb_define_module_function(mGtk, "timeout_remove", timeout_remove, 1);
    rb_define_module_function(mGtk, "idle_add", idle_add, -1);
    rb_define_module_function(mGtk, "idle_remove", idle_remove, 1);

    rb_define_module_function(mGtk, "set_warning_handler",
			      set_warning_handler, -1);
    rb_define_module_function(mGtk, "set_message_handler",
			      set_message_handler, -1);
    rb_define_module_function(mGtk, "set_print_handler",
			      set_print_handler, -1);

    /* Gdk module */
    /* GdkFont */
    rb_define_method(gdkFont, "==", gdkfnt_equal, 1);

    /* GdkBitmap */
    rb_define_method(gdkBitmap, "new", gdkbmap_s_new, 3);
    rb_define_singleton_method(gdkBitmap, "create_from_data",
			       gdkbmap_create_from_data, 4);

    /* GdkPixmap */
    rb_define_method(gdkPixmap, "new", gdkpmap_s_new, 4);
    rb_define_singleton_method(gdkPixmap, "create_from_xpm",
			       gdkpmap_create_from_xpm, 3);
    rb_define_singleton_method(gdkPixmap, "create_from_xpm_d",
			       gdkpmap_create_from_xpm, 3);

    /* GdkWindow */

    /* GdkImage */

    rb_define_const(mGtk, "VISIBLE", INT2FIX(GTK_VISIBLE));
    rb_define_const(mGtk, "MAPPED", INT2FIX(GTK_MAPPED));
    rb_define_const(mGtk, "UNMAPPED", INT2FIX(GTK_UNMAPPED));
    rb_define_const(mGtk, "REALIZED", INT2FIX(GTK_REALIZED));
    rb_define_const(mGtk, "SENSITIVE", INT2FIX(GTK_SENSITIVE));
    rb_define_const(mGtk, "PARENT_SENSITIVE", INT2FIX(GTK_PARENT_SENSITIVE));
    rb_define_const(mGtk, "NO_WINDOW", INT2FIX(GTK_NO_WINDOW));
    rb_define_const(mGtk, "HAS_FOCUS", INT2FIX(GTK_HAS_FOCUS));
    rb_define_const(mGtk, "CAN_FOCUS", INT2FIX(GTK_CAN_FOCUS));
    rb_define_const(mGtk, "HAS_DEFAULT", INT2FIX(GTK_HAS_DEFAULT));
    rb_define_const(mGtk, "CAN_DEFAULT", INT2FIX(GTK_CAN_DEFAULT));
    rb_define_const(mGtk, "PROPAGATE_STATE", INT2FIX(GTK_PROPAGATE_STATE));
    rb_define_const(mGtk, "ANCHORED", INT2FIX(GTK_ANCHORED));
    rb_define_const(mGtk, "BASIC", INT2FIX(GTK_BASIC));
    rb_define_const(mGtk, "USER_STYLE", INT2FIX(GTK_USER_STYLE));
    rb_define_const(mGtk, "REDRAW_PENDING", INT2FIX(GTK_REDRAW_PENDING));
    rb_define_const(mGtk, "RESIZE_PENDING", INT2FIX(GTK_RESIZE_PENDING));
    rb_define_const(mGtk, "RESIZE_NEEDED", INT2FIX(GTK_RESIZE_NEEDED));
    rb_define_const(mGtk, "HAS_SHAPE_MASK", INT2FIX(GTK_HAS_SHAPE_MASK));

    /* GtkWindowType */
    rb_define_const(mGtk, "WINDOW_TOPLEVEL", INT2FIX(GTK_WINDOW_TOPLEVEL));
    rb_define_const(mGtk, "WINDOW_DIALOG", INT2FIX(GTK_WINDOW_DIALOG));
    rb_define_const(mGtk, "WIN_POS_NONE", INT2FIX(GTK_WIN_POS_NONE));
    rb_define_const(mGtk, "WIN_POS_CENTER", INT2FIX(GTK_WIN_POS_CENTER));
    rb_define_const(mGtk, "WIN_POS_MOUSE", INT2FIX(GTK_WIN_POS_MOUSE));

    /* GtkDirectionType */
    rb_define_const(mGtk, "DIR_TAB_FORWARD", INT2FIX(GTK_DIR_TAB_FORWARD));
    rb_define_const(mGtk, "DIR_TAB_BACKWARD", INT2FIX(GTK_DIR_TAB_BACKWARD));
    rb_define_const(mGtk, "DIR_UP", INT2FIX(GTK_DIR_UP));
    rb_define_const(mGtk, "DIR_DOWN", INT2FIX(GTK_DIR_DOWN));
    rb_define_const(mGtk, "DIR_LEFT", INT2FIX(GTK_DIR_LEFT));
    rb_define_const(mGtk, "DIR_RIGHT", INT2FIX(GTK_DIR_RIGHT));

    /* GtkPolicyType */
    rb_define_const(mGtk, "POLICY_ALWAYS", INT2FIX(GTK_POLICY_ALWAYS));
    rb_define_const(mGtk, "POLICY_AUTOMATIC", INT2FIX(GTK_POLICY_AUTOMATIC));

    /* GtkSelectionMode */
    rb_define_const(mGtk, "SELECTION_SINGLE", INT2FIX(GTK_SELECTION_SINGLE));
    rb_define_const(mGtk, "SELECTION_BROWSE", INT2FIX(GTK_SELECTION_BROWSE));
    rb_define_const(mGtk, "SELECTION_MULTIPLE", INT2FIX(GTK_SELECTION_MULTIPLE));
    rb_define_const(mGtk, "SELECTION_EXTENDED", INT2FIX(GTK_SELECTION_EXTENDED));
    /* GtkPositionType */
    rb_define_const(mGtk, "POS_LEFT", INT2FIX(GTK_POS_LEFT));
    rb_define_const(mGtk, "POS_RIGHT", INT2FIX(GTK_POS_RIGHT));
    rb_define_const(mGtk, "POS_TOP", INT2FIX(GTK_POS_TOP));
    rb_define_const(mGtk, "POS_BOTTOM", INT2FIX(GTK_POS_BOTTOM));

    /* GtkShadowType */
    rb_define_const(mGtk, "SHADOW_NONE", INT2FIX(GTK_SHADOW_NONE));
    rb_define_const(mGtk, "SHADOW_IN", INT2FIX(GTK_SHADOW_IN));
    rb_define_const(mGtk, "SHADOW_OUT", INT2FIX(GTK_SHADOW_OUT));
    rb_define_const(mGtk, "SHADOW_ETCHED_IN", INT2FIX(GTK_SHADOW_ETCHED_IN));
    rb_define_const(mGtk, "SHADOW_ETCHED_OUT", INT2FIX(GTK_SHADOW_ETCHED_OUT));
    /* GtkStateType */
    rb_define_const(mGtk, "STATE_NORMAL", INT2FIX(GTK_STATE_NORMAL));
    rb_define_const(mGtk, "STATE_ACTIVE", INT2FIX(GTK_STATE_ACTIVE));
    rb_define_const(mGtk, "STATE_PRELIGHT", INT2FIX(GTK_STATE_PRELIGHT));
    rb_define_const(mGtk, "STATE_SELECTED", INT2FIX(GTK_STATE_SELECTED));
    rb_define_const(mGtk, "STATE_INSENSITIVE", INT2FIX(GTK_STATE_INSENSITIVE));
    /* GtkAttachOptions */
    rb_define_const(mGtk, "EXPAND", INT2FIX(GTK_EXPAND));
    rb_define_const(mGtk, "SHRINK", INT2FIX(GTK_SHRINK));
    rb_define_const(mGtk, "FILL", INT2FIX(GTK_FILL));
    /* GtkSubmenuDirection */
    rb_define_const(mGtk, "DIRECTION_LEFT", INT2FIX(GTK_DIRECTION_LEFT));
    rb_define_const(mGtk, "DIRECTION_RIGHT", INT2FIX(GTK_DIRECTION_RIGHT));
    /* GtkSubmenuPlacement */
    rb_define_const(mGtk, "TOP_BOTTOM", INT2FIX(GTK_TOP_BOTTOM));
    rb_define_const(mGtk, "LEFT_RIGHT", INT2FIX(GTK_LEFT_RIGHT));
    /* GtkMetricType */
    rb_define_const(mGtk, "PIXELS", INT2FIX(GTK_PIXELS));
    rb_define_const(mGtk, "INCHES", INT2FIX(GTK_INCHES));
    rb_define_const(mGtk, "CENTIMETERS", INT2FIX(GTK_CENTIMETERS));

    /* GtkArrowType */
    rb_define_const(mGtk, "ARROW_UP", INT2FIX(GTK_ARROW_UP));
    rb_define_const(mGtk, "ARROW_DOWN", INT2FIX(GTK_ARROW_DOWN));
    rb_define_const(mGtk, "ARROW_LEFT", INT2FIX(GTK_ARROW_LEFT));
    rb_define_const(mGtk, "ARROW_RIGHT", INT2FIX(GTK_ARROW_RIGHT));

    /* GtkPreviewType */
    rb_define_const(mGtk, "PREVIEW_COLOR", INT2FIX(GTK_PREVIEW_COLOR));
    rb_define_const(mGtk, "PREVIEW_GRAYSCALE", INT2FIX(GTK_PREVIEW_GRAYSCALE));

    rb_define_const(mGtk, "BUTTONBOX_DEFAULT", INT2FIX(GTK_BUTTONBOX_DEFAULT));
    rb_define_const(mGtk, "BUTTONBOX_SPREAD", INT2FIX(GTK_BUTTONBOX_SPREAD));
    rb_define_const(mGtk, "BUTTONBOX_EDGE", INT2FIX(GTK_BUTTONBOX_EDGE));
    rb_define_const(mGtk, "BUTTONBOX_START", INT2FIX(GTK_BUTTONBOX_START));
    rb_define_const(mGtk, "BUTTONBOX_END", INT2FIX(GTK_BUTTONBOX_END));

    /* GtkToolbarStyle */
    rb_define_const(mGtk, "TOOLBAR_ICONS", INT2FIX(GTK_TOOLBAR_ICONS));
    rb_define_const(mGtk, "TOOLBAR_TEXT", INT2FIX(GTK_TOOLBAR_TEXT));
    rb_define_const(mGtk, "TOOLBAR_BOTH", INT2FIX(GTK_TOOLBAR_BOTH));

    /* GtkOrientation */
    rb_define_const(mGtk, "ORIENTATION_HORIZONTAL", INT2FIX(GTK_ORIENTATION_HORIZONTAL));
    rb_define_const(mGtk, "ORIENTATION_VERTICAL", INT2FIX(GTK_ORIENTATION_VERTICAL));

    /* GdkExtensionMode */
    rb_define_const(mGdk, "EXTENSION_EVENTS_NONE", INT2FIX(GDK_EXTENSION_EVENTS_NONE));
    rb_define_const(mGdk, "EXTENSION_EVENTS_ALL", INT2FIX(GDK_EXTENSION_EVENTS_ALL));
    rb_define_const(mGdk, "EXTENSION_EVENTS_CURSOR", INT2FIX(GDK_EXTENSION_EVENTS_CURSOR));

    argc = RARRAY(rb_argv)->len;
    argv = ALLOCA_N(char*,argc+1);
    argv[0] = RSTRING(rb_argv0)->ptr;
    for (i=0;i<argc;i++) {
	if (TYPE(RARRAY(rb_argv)->ptr[i]) == T_STRING) {
	    argv[i+1] = RSTRING(RARRAY(rb_argv)->ptr[i])->ptr;
	}
	else {
	    argv[i+1] = "";
	}
    }
    argc++;
    {
	/* Gdk modifies sighandlers, sigh */
	RETSIGTYPE (*sigfunc[7])();

	sigfunc[0] = signal(SIGHUP, SIG_IGN);
	sigfunc[1] = signal(SIGINT, SIG_IGN);
	sigfunc[2] = signal(SIGQUIT, SIG_IGN);
	sigfunc[3] = signal(SIGBUS, SIG_IGN);
	sigfunc[4] = signal(SIGSEGV, SIG_IGN);
	sigfunc[5] = signal(SIGPIPE, SIG_IGN);
	sigfunc[6] = signal(SIGTERM, SIG_IGN);

	gdk_init(&argc, &argv);

	signal(SIGHUP,  sigfunc[0]);
	signal(SIGINT,  sigfunc[1]);
	signal(SIGQUIT, sigfunc[2]);
	signal(SIGBUS,  sigfunc[3]);
	signal(SIGSEGV, sigfunc[4]);
	signal(SIGPIPE, sigfunc[5]);
	signal(SIGTERM, sigfunc[6]);
    }

    for (i=1;i<argc;i++) {
	RARRAY(rb_argv)->ptr[i] = str_taint(str_new2(argv[i]));
    }
    RARRAY(rb_argv)->len = argc-1;

    id_call = rb_intern("call");
    id_gtkdata = rb_intern("gtkdata");
    id_relatives = rb_intern("relatives");
    id_init = rb_intern("initialize");
    gtk_idle_add((GtkFunction)idle, 0);

    g_set_error_handler(gtkerr);
    g_set_warning_handler(gtkerr);
    rb_global_variable(&warn_handler);
    rb_global_variable(&mesg_handler);
    rb_global_variable(&print_handler);
}
