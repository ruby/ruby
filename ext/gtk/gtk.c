/************************************************

  gtk.c -

  $Author$
  $Date$
  created at: Wed Jan  7 23:55:11 JST 1998

************************************************/

#include "ruby.h"
#include "rubysig.h"
#include <gtk/gtk.h>
#include <gdk/gdkx.h> /* for GDK_ROOT_WINDOW() */
#include <signal.h>

extern VALUE rb_argv, rb_argv0;
extern VALUE rb_cData;

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
static VALUE gCombo;
static VALUE gImage;
static VALUE gDrawArea;
static VALUE gEditable;
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
static VALUE gStatusBar;
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
static VALUE gRequisition;

static VALUE mRC;

static VALUE mGdk;

static VALUE gdkFont;
static VALUE gdkColor;
static VALUE gdkColormap;
static VALUE gdkDrawable;
static VALUE gdkPixmap;
static VALUE gdkBitmap;
static VALUE gdkWindow;
static VALUE gdkImage;
static VALUE gdkVisual;
static VALUE gdkGC;
static VALUE gdkRectangle;
static VALUE gdkGCValues;
static VALUE gdkSegment;
static VALUE gdkWindowAttr;
static VALUE gdkCursor;
static VALUE gdkAtom;
static VALUE gdkColorContext;
static VALUE gdkEvent;

static VALUE gdkEventType;
static VALUE gdkEventAny;
static VALUE gdkEventExpose;
static VALUE gdkEventNoExpose;
static VALUE gdkEventVisibility;
static VALUE gdkEventMotion;
static VALUE gdkEventButton;
static VALUE gdkEventKey;
static VALUE gdkEventCrossing;
static VALUE gdkEventFocus;
static VALUE gdkEventConfigure;
static VALUE gdkEventProperty;
static VALUE gdkEventSelection;
static VALUE gdkEventProximity;
static VALUE gdkEventDragBegin;
static VALUE gdkEventDragRequest;
static VALUE gdkEventDropEnter;
static VALUE gdkEventDropLeave;
static VALUE gdkEventDropDataAvailable;
static VALUE gdkEventClient;
static VALUE gdkEventOther;

ID id_gtkdata, id_relatives, id_call;

static void gobj_mark();

static GtkObject*
get_gobject(obj)
    VALUE obj;
{
    struct RData *data;
    GtkObject *gtkp;

    if (NIL_P(obj)) return NULL;

    Check_Type(obj, T_OBJECT);
    data = RDATA(rb_ivar_get(obj, id_gtkdata));
    if (NIL_P(data) || data->dmark != gobj_mark) {
	rb_raise(rb_eTypeError, "not a Gtk object");
    }
    Data_Get_Struct(data, GtkObject, gtkp);
    if (!gtkp) {
	rb_raise(rb_eArgError, "destroyed GtkObject");
    }
    if (!GTK_IS_OBJECT(gtkp)) {
	rb_raise(rb_eTypeError, "not a GtkObject");
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

    if (NIL_P(ary) || TYPE(ary) != T_ARRAY) {
	ary = rb_ary_new();
	rb_ivar_set(obj, id_relatives, ary);
    }
    rb_ary_push(ary, relative);
}

static VALUE gtk_object_list;

static void
gobj_mark(obj)
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

    rb_ary_delete(gtk_object_list, obj);
    data = RDATA(rb_ivar_get(obj, id_gtkdata));
    data->dfree = 0;
    data->data = 0;
}

static void
set_gobject(obj, gtkobj)
    VALUE obj;
    GtkObject *gtkobj;
{
    VALUE data;

    data = Data_Wrap_Struct(rb_cData, gobj_mark, 0, gtkobj);
    gtk_object_set_user_data(gtkobj, (gpointer)obj);

    rb_ivar_set(obj, id_gtkdata, data);
    gtk_signal_connect(gtkobj, "destroy",
		       (GtkSignalFunc)delete_gobject, (gpointer)obj);
    rb_ary_push(gtk_object_list, obj);
}

static VALUE
make_gobject(klass, gtkobj)
    VALUE klass;
    GtkObject *gtkobj;
{
    VALUE obj = rb_obj_alloc(klass);

    set_gobject(obj, gtkobj);
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
    return make_gobject(klass, GTK_OBJECT(widget));
}

static VALUE
make_gstyle(style)
    GtkStyle *style;
{
    VALUE obj;

    gtk_style_ref(style);
    return Data_Wrap_Struct(gStyle, 0, gtk_style_unref, style);
}

static GtkStyle*
get_gstyle(style)
    VALUE style;
{
    GtkStyle *gstyle;

    if (NIL_P(style)) return NULL;
    if (!rb_obj_is_instance_of(style, gStyle)) {
	rb_raise(rb_eTypeError, "not a GtkStyle");
    }
    Data_Get_Struct(style, GtkStyle, gstyle);

    return gstyle;
}

static VALUE
make_gtkacceltbl(tbl)
    GtkAcceleratorTable *tbl;
{
    VALUE obj;

    gtk_accelerator_table_ref(tbl);
    return Data_Wrap_Struct(gAcceleratorTable, 0,
			    gtk_accelerator_table_unref, tbl);
}

static GtkAcceleratorTable*
get_gtkacceltbl(value)
    VALUE value;
{
    GtkAcceleratorTable *tbl;

    if (NIL_P(value)) return NULL;

    if (!rb_obj_is_instance_of(value, gAcceleratorTable)) {
	rb_raise(rb_eTypeError, "not an AcceleratorTable");
    }
    Data_Get_Struct(value, GtkAcceleratorTable, tbl);

    return tbl;
}

static VALUE
make_gtkprevinfo(info)
    GtkPreviewInfo *info;
{
    return Data_Wrap_Struct(gPreviewInfo, 0, 0, info);
}

static GtkPreviewInfo*
get_gtkprevinfo(value)
    VALUE value;
{
    GtkPreviewInfo *info;

    if (NIL_P(value)) return NULL;

    if (!rb_obj_is_instance_of(value, gPreviewInfo)) {
	rb_raise(rb_eTypeError, "not a PreviewInfo");
    }
    Data_Get_Struct(value, GtkPreviewInfo, info);

    return info;
}

static VALUE
make_gdkfont(font)
    GdkFont *font;
{
    VALUE obj;

    gdk_font_ref(font);
    obj = Data_Wrap_Struct(gdkFont, 0, gdk_font_unref, font);

    return obj;
}

static GdkFont*
get_gdkfont(font)
    VALUE font;
{
    GdkFont *gfont;

    if (NIL_P(font)) return NULL;

    if (!rb_obj_is_instance_of(font, gdkFont)) {
	rb_raise(rb_eTypeError, "not a GdkFont");
    }
    Data_Get_Struct(font, GdkFont, gfont);

    return gfont;
}

static VALUE
gdkfnt_load_font(self, name)
    VALUE self, name;
{
    GdkFont *font;

    font = gdk_font_load(STR2CSTR(name));
    return Data_Wrap_Struct(gdkFont, 0, gdk_font_unref, font);
	/*    return make_gdkfont(new); */ 
}
static VALUE
gdkfnt_load_fontset(self, name)
    VALUE self, name;
{
    GdkFont *new;

    new = gdk_fontset_load(STR2CSTR(name));
    return make_gdkfont(new);
}
static VALUE
gdkfnt_new(self, name)
    VALUE self, name;
{
  char *cname = STR2CSTR(name);
  return (strchr(cname, ',') == NULL)
	? gdkfnt_load_font(self, name)
	: gdkfnt_load_fontset(self, name);
}
static VALUE
gdkfnt_string_width(self, str)
    VALUE self, str;
{
  int w;

  w = gdk_string_width(get_gdkfont(self), STR2CSTR(str));
  return INT2NUM(w);
}
static VALUE
gdkfnt_ascent(self)
    VALUE self;
{
  return INT2NUM(get_gdkfont(self)->ascent);
}
static VALUE
gdkfnt_descent(self)
    VALUE self;
{
  return INT2NUM(get_gdkfont(self)->descent);
}

static VALUE
gdkfnt_equal(fn1, fn2)
    VALUE fn1, fn2;
{
    if (gdk_font_equal(get_gdkfont(fn1), get_gdkfont(fn2)))
	return Qtrue;
    return Qfalse;
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
    data = Data_Wrap_Struct(klass, 0, free, copy);

    return data;
}

static gpointer
get_tobj(obj, klass)
    VALUE obj, klass;
{
    void *ptr;

    if (NIL_P(obj)) return NULL;

    if (!rb_obj_is_instance_of(obj, klass)) {
	rb_raise(rb_eTypeError, "not a %s", rb_class2name(klass));
    }
    Data_Get_Struct(obj, void, ptr);

    return ptr;
}

#define make_gdkcolor(c) make_tobj(c, gdkColor, sizeof(GdkColor))
#define get_gdkcolor(c) ((GdkColor*)get_tobj(c, gdkColor))

#define make_gdksegment(c) make_tobj(c, gdkSegment, sizeof(GdkSegment))
#define get_gdksegment(c) ((GdkSegment*)get_tobj(c, gdkSegment))

#define make_gdkwinattr(c) make_tobj(c, gdkWindowAttr, sizeof(GdkWindowAttr))
#define get_gdkwinattr(c) ((GdkWindowAttr*)get_tobj(c, gdkWindowAttr))

#define make_gdkwinattr(c) make_tobj(c, gdkWindowAttr, sizeof(GdkWindowAttr))
#define get_gdkwinattr(c) ((GdkWindowAttr*)get_tobj(c, gdkWindowAttr))

#define make_gallocation(c) make_tobj(c, gAllocation, sizeof(GtkAllocation))
#define get_gallocation(c) ((GtkAllocation*)get_tobj(c, gAllocation))

#define make_grequisition(c) make_tobj(c, gRequisition, sizeof(GtkRequisition))
#define get_grequisition(c) ((GtkRequisition*)get_tobj(c, gRequisition))

#define make_gdkrectangle(r) make_tobj(r, gdkRectangle, sizeof(GdkRectangle))
#define get_gdkrectangle(r) ((GdkRectangle*)get_tobj(r, gdkRectangle))

static VALUE
make_gdkcmap(cmap)
    GdkColormap *cmap;
{
    gdk_colormap_ref(cmap);
    return Data_Wrap_Struct(gdkColormap, 0, gdk_colormap_unref, cmap);
}

static GdkColormap*
get_gdkcmap(cmap)
    VALUE cmap;
{
    GdkColormap *gcmap;

    if (NIL_P(cmap)) return NULL;

    if (!rb_obj_is_kind_of(cmap, gdkColormap)) {
	rb_raise(rb_eTypeError, "not a GdkColormap");
    }
    Data_Get_Struct(cmap, GdkColormap, gcmap);

    return gcmap;
}

static VALUE
make_gdkvisual(visual)
    GdkVisual *visual;
{
    gdk_visual_ref(visual);
    return Data_Wrap_Struct(gdkVisual, 0, gdk_visual_unref, visual);
}

static GdkVisual*
get_gdkvisual(visual)
    VALUE visual;
{
    GdkVisual *gvisual;

    if (NIL_P(visual)) return NULL;

    if (!rb_obj_is_kind_of(visual, gdkVisual)) {
	rb_raise(rb_eTypeError, "not a GdkVisual");
    }
    Data_Get_Struct(visual, GdkVisual, gvisual);

    return gvisual;
}

static VALUE
make_gdkdraw(klass, draw, ref, unref)
    VALUE klass;
    GdkDrawable *draw;
    void (*ref)();
    void (*unref)();
{
    (*ref)(draw);
    return Data_Wrap_Struct(klass, 0, unref, draw);
}

#define make_gdkwindow2(c,w) make_gdkdraw(c,(w),gdk_window_ref,gdk_window_unref)
#define make_gdkbitmap2(c,w) make_gdkdraw(c,(w),gdk_bitmap_ref,gdk_bitmap_unref)
#define make_gdkpixmap2(c,w) make_gdkdraw(c,(w),gdk_pixmap_ref,gdk_pixmap_unref)
#define make_gdkwindow(w) make_gdkwindow2(gdkWindow,(w))
#define make_gdkbitmap(w) make_gdkbitmap2(gdkBitmap,(w))
#define make_gdkpixmap(w) make_gdkpixmap2(gdkPixmap,(w))

static GdkWindow*
get_gdkdraw(draw, klass, kname)
    VALUE draw, klass;
    char *kname;
{
    GdkDrawable *d;

    if (NIL_P(draw)) return NULL;

    if (!rb_obj_is_kind_of(draw, klass)) {
	rb_raise(rb_eTypeError, "not a %s", kname);
    }
    Data_Get_Struct(draw, GdkDrawable, d);

    return d;
}

#define get_gdkdrawable(w) get_gdkdraw((w),gdkDrawable,"GdkDrawable")
#define get_gdkwindow(w) get_gdkdraw((w),gdkWindow,"GdkWindow")
#define get_gdkpixmap(w) get_gdkdraw((w),gdkPixmap,"GdkPixmap")
#define get_gdkbitmap(w) get_gdkdraw((w),gdkBitmap,"GdkBitmap")

static VALUE
gdkdraw_get_geometry(self)
    VALUE self;
{
    gint x, y, width, height, depth;

    gdk_window_get_geometry(get_gdkdrawable(self),
			    &x, &y, &width, &height, &depth);
    return rb_ary_new3(5, INT2NUM(x), INT2NUM(y),
		    INT2NUM(width), INT2NUM(height), INT2NUM(depth));
}

static VALUE
gdkpmap_s_new(self, win, w, h, depth)
    VALUE self, win, w, h, depth;
{
    GdkPixmap *new;
    GdkWindow *window = get_gdkwindow(win);

    new = gdk_pixmap_new(window, NUM2INT(w), NUM2INT(h), NUM2INT(depth));
    return make_gdkpixmap2(self,new);
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
    return make_gdkpixmap2(self,new);
}

static VALUE
gdkpmap_create_from_xpm(self, win, tcolor, fname)
    VALUE self, win, tcolor, fname;
{
    GdkPixmap *new;
    GdkBitmap *mask;
    GdkWindow *window = get_gdkwindow(win);

    new = gdk_pixmap_create_from_xpm(window, &mask,
				     get_gdkcolor(tcolor),
				     STR2CSTR(fname));
    if (!new) {
	rb_raise(rb_eArgError, "Pixmap not created from %s", STR2CSTR(fname));
    }
    return rb_assoc_new(make_gdkpixmap2(self,new),
		     make_gdkbitmap(mask));
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
	buf[i] = STR2CSTR(RARRAY(data)->ptr[i]);
    }

    new = gdk_pixmap_create_from_xpm_d(window, &mask,
				       get_gdkcolor(tcolor),
				       buf);

    return rb_assoc_new(make_gdkpixmap2(self,new),
		     make_gdkbitmap(mask));
}

static VALUE
gdkbmap_s_new(self, win, w, h)
    VALUE self, win, w, h;
{
    GdkPixmap *new;
    GdkWindow *window = get_gdkwindow(win);

    new = gdk_pixmap_new(window, NUM2INT(w), NUM2INT(h), 1);
    return make_gdkpixmap2(self,new);
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
    return make_gdkbitmap2(self,new);
}

static VALUE
make_gdkimage(image)
    GdkImage *image;
{
    return Data_Wrap_Struct(gdkImage, 0, gdk_image_destroy, image);
}

static GdkImage*
get_gdkimage(image)
    VALUE image;
{
    GdkImage *gimage;

    if (NIL_P(image)) return NULL;

    if (!rb_obj_is_instance_of(image, gdkImage)) {
	rb_raise(rb_eTypeError, "not a GdkImage");
    }
    Data_Get_Struct(image, GdkImage, gimage);
    if (gimage == 0) {
	rb_raise(rb_eArgError, "destroyed GdkImage");
    }

    return gimage;
}

static VALUE
gdkimage_s_newbmap(klass, visual, data, w, h)
    VALUE klass, visual, data, w, h;
{
    GdkImage *image;

    Check_Type(data, T_STRING);
    if (RSTRING(data)->len < w * h) {
	rb_raise(rb_eArgError, "data too short");
    }
    return make_gdkimage(gdk_image_new_bitmap(get_gdkvisual(visual),
					      RSTRING(data)->ptr,
					      NUM2INT(w),NUM2INT(h)));
}

static VALUE
gdkimage_s_new(klass, type, visual, w, h)
    VALUE klass, type, visual, w, h;
{
    GdkImage *image;

    return make_gdkimage(gdk_image_new((GdkImageType)NUM2INT(type),
				       get_gdkvisual(visual),
				       NUM2INT(w),NUM2INT(h)));
}

static VALUE
gdkimage_s_get(klass, win, x, y, w, h)
    VALUE klass, win, x, y, w, h;
{
    GdkImage *image;

    return make_gdkimage(gdk_image_get(get_gdkwindow(win),
				       NUM2INT(x),NUM2INT(y),
				       NUM2INT(w),NUM2INT(h)));
}

static VALUE
gdkimage_put_pixel(self, x, y, pix)
    VALUE self, x, y, pix;
{
    gdk_image_put_pixel(get_gdkimage(self),
			NUM2INT(x),NUM2INT(y),NUM2INT(pix));
    return self;
}

static VALUE
gdkimage_get_pixel(self, x, y)
    VALUE self, x, y;
{
    guint32 pix;

    pix = gdk_image_get_pixel(get_gdkimage(self), NUM2INT(x),NUM2INT(y));
    return INT2NUM(pix);
}

static VALUE
gdkimage_destroy(self)
    VALUE self;
{
    gdk_image_destroy(get_gdkimage(self));
    DATA_PTR(self) = 0;
    return Qnil;
}

static VALUE
gdkwin_get_pointer(self)
     VALUE self;
{
  int x, y;
  GdkModifierType state;
  gdk_window_get_pointer(get_gdkwindow(self), &x, &y, &state);
  return rb_ary_new3(3, INT2FIX(x), INT2FIX(y), INT2FIX((int)state));

}

static VALUE
gdkwin_pointer_grab(self, owner_events, event_mask, confine_to, cursor, time)
     VALUE self, owner_events, event_mask, confine_to, cursor, time;
{
  gdk_pointer_grab(get_gdkwindow(self),
		   NUM2INT(owner_events),
		   NUM2INT(event_mask),
		   NULL,  /*get_gdkwindow(confine_to),*/
		   NULL,  /*get_gdkcursor(cursor),*/
		   NUM2INT(time));
  return self;
}

static VALUE
gdkwin_pointer_ungrab(self, time)
     VALUE self, time;
{
  gdk_pointer_ungrab(NUM2INT(time));
  return self;
}

static VALUE
gdkwin_foreign_new(self, anid)
     VALUE self, anid;
{
  GdkWindow *window;
  window = gdk_window_foreign_new(NUM2INT(anid));
  return make_gdkwindow(window);
}

static VALUE
gdkwin_root_window(self)
     VALUE self;
{
  return INT2NUM(GDK_ROOT_WINDOW() );
}

static VALUE
gdkwin_clear(self)
     VALUE self;
{
  gdk_window_clear(get_gdkwindow(self));
  return self;
}
static VALUE
gdkwin_clear_area(self, x,y,w,h)
     VALUE self,x,y,w,h;
{
  gdk_window_clear_area(get_gdkwindow(self),
						NUM2INT(x), NUM2INT(y), NUM2INT(w), NUM2INT(h));
  return self;
}
static VALUE
gdkwin_clear_area_e(self, x,y,w,h)
     VALUE self,x,y,w,h;
{
  gdk_window_clear_area_e(get_gdkwindow(self),
						  NUM2INT(x), NUM2INT(y), NUM2INT(w), NUM2INT(h));
  return self;
}

static VALUE
gdkwin_set_background(self, c)
    VALUE self, c;
{
  GdkColor color;
  color.pixel = NUM2INT(c);
  gdk_window_set_background(get_gdkwindow(self), &color);
  return self;
}

static VALUE
gdkwin_set_back_pixmap(self, pixmap, parent_relative)
    VALUE self, pixmap, parent_relative;
{
  gdk_window_set_back_pixmap(get_gdkwindow(self), get_gdkpixmap(pixmap),
							 NUM2INT(parent_relative));
  return self;
}


static VALUE
make_gdkevent(event)
    GdkEvent *event;
{
    event = gdk_event_copy(event);
    switch (event->type) {
    case GDK_EXPOSE:
    case GDK_NO_EXPOSE:
      return Data_Wrap_Struct(gdkEventExpose, 0, gdk_event_free, event);
      break;
    case GDK_MOTION_NOTIFY:
      return Data_Wrap_Struct(gdkEventMotion, 0, gdk_event_free, event);
      break;
    case GDK_BUTTON_PRESS:
    case GDK_2BUTTON_PRESS:
    case GDK_3BUTTON_PRESS:
      return Data_Wrap_Struct(gdkEventButton, 0, gdk_event_free, event);
      break;
    default:
      return Data_Wrap_Struct(gdkEvent, 0, gdk_event_free, event);
    }
}

static GdkEvent*
get_gdkevent(event)
    VALUE event;
{
    GdkEvent *gevent;

    if (NIL_P(event)) return NULL;

    if (!rb_obj_is_instance_of(event, gdkEvent)) {
	rb_raise(rb_eTypeError, "not a GdkEvent");
    }
    Data_Get_Struct(event, GdkEvent, gevent);

    return gevent;
}

static VALUE
make_gdkgc(gc)
    GdkGC *gc;
{
    gdk_gc_ref(gc);
    return Data_Wrap_Struct(gdkGC, 0, gdk_gc_destroy, gc);
}

static GdkGC*
get_gdkgc(gc)
    VALUE gc;
{
    GdkGC *ggc;

    if (NIL_P(gc)) return NULL;

    if (!rb_obj_is_instance_of(gc, gdkGC)) {
	rb_raise(rb_eTypeError, "not a GdkGC");
    }
    Data_Get_Struct(gc, GdkGC, ggc);
    if (ggc == 0) {
	rb_raise(rb_eArgError, "destroyed GdkGC");
    }

    return ggc;
}

static VALUE
gdkgc_s_new(self, win)
    VALUE self, win;
{
    return make_gdkgc(gdk_gc_new(get_widget(win)->window));
}

static VALUE
gdkgc_copy(self, copy)
    VALUE copy;
{
    gdk_gc_copy(get_gdkgc(self), get_gdkgc(copy));
    return copy;
}

static VALUE
gdkgc_destroy(self)
    VALUE self;
{
    gdk_gc_destroy(get_gdkgc(self));
    DATA_PTR(self) = 0;
    return Qnil;
}

static VALUE
gdkgc_set_function(self, func)
    VALUE func;
{
  GdkFunction f;
  f = (GdkFunction) NUM2INT(func);
  if (f != GDK_COPY && f != GDK_INVERT && f != GDK_XOR)
	ArgError("function out of range");
  
  gdk_gc_set_function(get_gdkgc(self), f);
  return func;
}

static VALUE
gdkgc_set_foreground(self, pix)
    VALUE pix;
{
  GdkColor c;
  c.pixel = NUM2INT(pix);
  gdk_gc_set_foreground(get_gdkgc(self), &c);
  return pix;
}
static VALUE
gdkgc_set_background(self, pix)
    VALUE pix;
{
  GdkColor c;
  c.pixel = NUM2INT(pix);
  gdk_gc_set_background(get_gdkgc(self), &c);
  return pix;
}
static VALUE
gdkgc_set_clip_mask(self, mask)
    VALUE mask;
{
  gdk_gc_set_clip_mask(get_gdkgc(self), get_gdkbitmap(mask));
  return mask;
}
static VALUE
gdkgc_set_clip_origin(self, x, y)
    VALUE x, y;
{
  gdk_gc_set_clip_origin(get_gdkgc(self), NUM2INT(x), NUM2INT(y));
  return self;
}
static VALUE
gdkgc_set_clip_rectangle(self, rectangle)
	 VALUE rectangle;
{
  gdk_gc_set_clip_rectangle(get_gdkgc(self), get_gdkrectangle(rectangle));
  return rectangle;
}
/*
static VALUE
gdkgc_set_clip_region(self, region)
	 VALUE region;
{
  gdk_gc_set_clip_region(get_gdkgc(self), get_gdkregion(region));
  return region;
}
*/

static VALUE
glist2ary(list)
    GList *list; 
{
    VALUE ary = rb_ary_new();

    while (list) {
	rb_ary_push(ary, get_value_from_gobject(GTK_OBJECT(list->data)));
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
    VALUE ary = rb_ary_new();

    while (list) {
	rb_ary_push(ary, get_value_from_gobject(GTK_OBJECT(list->data)));
	list = list->next;
    }

    return ary;
}

static VALUE
arg_to_value(arg)
    GtkArg *arg;
{
    switch (GTK_FUNDAMENTAL_TYPE(arg->type)) {
      case GTK_TYPE_CHAR:
	return INT2FIX(GTK_VALUE_CHAR(*arg));
	break;

      case GTK_TYPE_BOOL:
      case GTK_TYPE_INT:
      case GTK_TYPE_ENUM:
      case GTK_TYPE_FLAGS:
	return INT2NUM(GTK_VALUE_INT(*arg));
	break;

      case GTK_TYPE_UINT:
	return INT2NUM(GTK_VALUE_UINT(*arg));
	break;
      case GTK_TYPE_LONG:
	return INT2NUM(GTK_VALUE_LONG(*arg));
	break;
      case GTK_TYPE_ULONG:
	return INT2NUM(GTK_VALUE_ULONG(*arg));
	break;

      case GTK_TYPE_FLOAT:
	return rb_float_new(GTK_VALUE_FLOAT(*arg));
	break;

      case GTK_TYPE_STRING:
	return rb_str_new2(GTK_VALUE_STRING(*arg));
	break;

      case GTK_TYPE_OBJECT:
	return get_value_from_gobject(GTK_VALUE_OBJECT(*arg));
	break;
	    
      case GTK_TYPE_SIGNAL:
	/* signal type?? */
	goto unsupported;

      case GTK_TYPE_BOXED:
	if (arg->type == GTK_TYPE_GDK_EVENT) {
	    return make_gdkevent(GTK_VALUE_BOXED(*arg));
	}
#ifdef GTK_TYPE_GDK_COLORMAP
	else if (arg->type == GTK_TYPE_GDK_COLORMAP) {
	    return make_gdkcmap(GTK_VALUE_BOXED(*arg));
	}
#endif
#ifdef GTK_TYPE_GDK_FONT
	else if (arg->type == GTK_TYPE_GDK_FONT) {
	    return make_gdkfont(GTK_VALUE_BOXED(*arg));
	}
#endif
#ifdef GTK_TYPE_GDK_PIXMAP
	else if (arg->type == GTK_TYPE_GDK_PIXMAP) {
	    return make_gdkpixmap(GTK_VALUE_BOXED(*arg));
	}
#endif
#ifdef GTK_TYPE_GDK_VISUAL
	else if (arg->type == GTK_TYPE_GDK_VISUAL) {
	    return make_gdkvisual(GTK_VALUE_BOXED(*arg));
	}
#endif
#ifdef GTK_TYPE_ACCELERATOR_TABLE
	else if (arg->type == GTK_TYPE_ACCELERATOR_TABLE) {
	    return make_gtkacceltbl(GTK_VALUE_BOXED(*arg));
	}
#endif
#ifdef GTK_TYPE_STYLE
	else if (arg->type == GTK_TYPE_STYLE) {
	    return make_gstyle(GTK_VALUE_BOXED(*arg));
	}
#endif
#ifdef GTK_TYPE_TOOLTIPS
	else if (arg->type == GTK_TYPE_TOOLTIPS) {
	    return make_gobject(gTooltips, GTK_OBJECT(GTK_VALUE_BOXED(*arg)));
	}
#endif
	else {
	    goto unsupported;
	}

      case GTK_TYPE_POINTER:
	return get_value_from_gobject(GTK_VALUE_OBJECT(*arg));
	break;

      case GTK_TYPE_INVALID:
      case GTK_TYPE_NONE:
      case GTK_TYPE_FOREIGN:
      case GTK_TYPE_CALLBACK:
      case GTK_TYPE_ARGS:
      case GTK_TYPE_C_CALLBACK:
      unsupported:
      default:
	rb_raise(rb_eTypeError, "unsupported arg type %s (fundamental type %s)",
		  gtk_type_name(arg->type),
		  gtk_type_name(GTK_FUNDAMENTAL_TYPE(arg->type)));
	break;
    }
}

static void
signal_setup_args(obj, sig, argc, params, args)
    VALUE obj;
    ID sig;
    int argc;
    GtkArg *params;
    VALUE args;
{
    int i;
    char *signame = rb_id2name(sig);

    if (rb_obj_is_kind_of(obj, gWidget)) {
	if (strcmp(signame, "draw") == 0) {
	    rb_ary_push(args, make_gdkrectangle(GTK_VALUE_POINTER(params[0])));
	    return;
	}
	if (strcmp(signame, "size_request") == 0) {
	    rb_ary_push(args, make_grequisition(GTK_VALUE_POINTER(params[0])));
	    return;
	}
	if (strcmp(signame, "size_allocate") == 0) {
	    rb_ary_push(args, make_gallocation(GTK_VALUE_POINTER(params[0])));
	    return;
	}
    }
    if (rb_obj_is_kind_of(obj, gWindow)) {
	if (strcmp(signame, "move_resize") == 0) {
	    rb_ary_push(args, INT2NUM(*GTK_RETLOC_INT(params[0])));
	    rb_ary_push(args, INT2NUM(*GTK_RETLOC_INT(params[1])));
	    rb_ary_push(args, INT2NUM(GTK_VALUE_INT(params[3])));
	    rb_ary_push(args, INT2NUM(GTK_VALUE_INT(params[4])));
	    return;
	}
	if (strcmp(signame, "set_focus") == 0) {
	    rb_ary_push(args, get_value_from_gobject(GTK_VALUE_POINTER(params[0])));
	    return;
	}
    }
    if (rb_obj_is_kind_of(obj, gEntry)) {
	if (strcmp(signame, "insert_position") == 0) {
	    rb_ary_push(args, INT2NUM(*GTK_RETLOC_INT(params[0])));
	    return;
	}
    }
    if (rb_obj_is_kind_of(obj, gCList)) {
	if (strcmp(signame, "select_row") == 0 ||
	    strcmp(signame, "unselect_row") == 0) {
	    rb_ary_push(args, INT2NUM(GTK_VALUE_INT(params[0])));
	    rb_ary_push(args, INT2NUM(GTK_VALUE_INT(params[1])));
	    if (GTK_VALUE_POINTER(params[2]))
		rb_ary_push(args, make_gdkevent(GTK_VALUE_POINTER(params[2])));
	    else
		rb_ary_push(args, Qnil);
	    return;
	}
    }

    for (i=0; i<argc; i++) {
	rb_ary_push(args, arg_to_value(params));
	params++;
    }
}

static void
arg_set_value(arg, value)
    GtkArg *arg;
    VALUE value;
{
    char *type = 0;

    switch (GTK_FUNDAMENTAL_TYPE(arg->type)) {
      case GTK_TYPE_NONE:
	break;

      case GTK_TYPE_CHAR:
	*GTK_RETLOC_CHAR(*arg) = NUM2INT(value);
	break;
      case GTK_TYPE_BOOL:
      case GTK_TYPE_INT:
      case GTK_TYPE_ENUM:
      case GTK_TYPE_FLAGS:
	*GTK_RETLOC_INT(*arg) = NUM2INT(value);
	break;
      case GTK_TYPE_UINT:
	*GTK_RETLOC_UINT(*arg) = NUM2INT(value);
	break;
      case GTK_TYPE_LONG:
	*GTK_RETLOC_LONG(*arg) = NUM2INT(value);
	break;
      case GTK_TYPE_ULONG:
	*GTK_RETLOC_ULONG(*arg) = NUM2INT(value);
	break;

      case GTK_TYPE_FLOAT:
	value = rb_Float(value);
	*GTK_RETLOC_FLOAT(*arg) = (float)RFLOAT(value)->value;
	break;

      case GTK_TYPE_STRING:
	*GTK_RETLOC_STRING(*arg) = STR2CSTR(value);
	break;

      case GTK_TYPE_OBJECT:
	*GTK_RETLOC_OBJECT(*arg) = get_gobject(value);
	break;
	    
      case GTK_TYPE_POINTER:
	*GTK_RETLOC_POINTER(*arg) = (gpointer)value;
	break;

      case GTK_TYPE_BOXED:
	if (arg->type == GTK_TYPE_GDK_EVENT)
	    GTK_VALUE_BOXED(*arg) = get_gdkevent(value);
#ifdef GTK_TYPE_GDK_COLORMAP
	else if (arg->type == GTK_TYPE_GDK_COLORMAP)
	    GTK_VALUE_BOXED(*arg) = get_gdkcmap(value);
#endif
#ifdef GTK_TYPE_GDK_FONT
	else if (arg->type == GTK_TYPE_GDK_FONT)
	    GTK_VALUE_BOXED(*arg) = get_gdkfont(value);
#endif
#ifdef GTK_TYPE_GDK_PIXMAP
	else if (arg->type == GTK_TYPE_GDK_PIXMAP)
	    GTK_VALUE_BOXED(*arg) = get_gdkpixmap(value);
#endif
#ifdef GTK_TYPE_GDK_VISUAL
	else if (arg->type == GTK_TYPE_GDK_VISUAL)
	    GTK_VALUE_BOXED(*arg) = get_gdkvisual(value);
#endif
#ifdef GTK_TYPE_ACCELERATOR_TABLE
	else if (arg->type == GTK_TYPE_ACCELERATOR_TABLE)
	    GTK_VALUE_BOXED(*arg) = get_gtkacceltbl(value);
#endif
#ifdef GTK_TYPE_STYLE
	else if (arg->type == GTK_TYPE_STYLE)
	    GTK_VALUE_BOXED(*arg) = get_gstyle(value);
#endif
#ifdef GTK_TYPE_TOOLTIPS
	else if (arg->type == GTK_TYPE_TOOLTIPS)
	    GTK_VALUE_BOXED(*arg) = get_widget(value);
#endif
	else
	    goto unsupported;

      unsupported:
      case GTK_TYPE_INVALID:
      case GTK_TYPE_FOREIGN:
      case GTK_TYPE_CALLBACK:
      case GTK_TYPE_ARGS:
      case GTK_TYPE_SIGNAL:
      case GTK_TYPE_C_CALLBACK:
      default:
	rb_raise(rb_eTypeError, "unsupported return type %s (fundamental type %s)",
		  gtk_type_name(arg->type),
		  gtk_type_name(GTK_FUNDAMENTAL_TYPE(arg->type)));
	break;
    }
}

static void
signal_callback(widget, data, nparams, params)
    GtkWidget *widget;
    VALUE data;
    int nparams;
    GtkArg *params;
{
    VALUE self = get_value_from_gobject(GTK_OBJECT(widget));
    VALUE proc = RARRAY(data)->ptr[0];
    VALUE a = RARRAY(data)->ptr[2];
    ID id = NUM2INT(RARRAY(data)->ptr[1]);
    VALUE result = Qnil;
    VALUE args = rb_ary_new2(nparams+1+RARRAY(a)->len);
    int i;

    signal_setup_args(self, id, nparams, params, args);
    for (i=0; i<RARRAY(a)->len; i++) {
	rb_ary_push(args, RARRAY(a)->ptr[i]);
    }
    if (NIL_P(proc)) {
	if (rb_respond_to(self, id)) {
	    result = rb_apply(self, id, args);
	}
    }
    else {
	rb_ary_unshift(args, self);
	result = rb_apply(proc, id_call, args);
    }
    arg_set_value(params+nparams, result);
}

static void
exec_callback(widget, proc)
    GtkWidget *widget;
    VALUE proc;
{
    rb_funcall(proc, id_call, 1, get_value_from_gobject(GTK_OBJECT(widget)));
}

static VALUE
gobj_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    rb_raise(rb_eRuntimeError, "can't instantiate class %s", rb_class2name(self));
}

static VALUE
gobj_smethod_added(self, id)
    VALUE self, id;
{
    GtkObject *obj = get_gobject(self);
    char *name = rb_id2name(NUM2INT(id));
    
    if (gtk_signal_lookup(name, GTK_OBJECT_TYPE(obj))) {
	VALUE data = rb_ary_new3(3, Qnil, id, rb_ary_new2(0));

	add_relative(self, data);
	gtk_signal_connect_interp(obj, name,
				  signal_callback, (gpointer)data,
				  NULL, 0);
    }
    return Qnil;
}

static VALUE
nil()
{
    return Qnil;
}

static GtkObject*
try_get_gobject(self)
    VALUE self;
{
    return (GtkObject*)rb_rescue((VALUE(*)())get_gobject, self, nil, 0);
}

static VALUE
grb_obj_equal(self, other)
    VALUE self, other;
{
    if (self == other) return Qtrue;
    if (get_gobject(self) == try_get_gobject(other)) return Qtrue;
    return Qfalse;
}

static VALUE
gobj_inspect(self)
    VALUE self;
{
    VALUE iv = rb_ivar_get(self, id_gtkdata);
    char *cname = rb_class2name(CLASS_OF(self));
    char *s;

    s = ALLOCA_N(char, strlen(cname)+8+16+1); /* 6:tags 16:addr 1:eos */
    if (NIL_P(iv) || RDATA(iv)->data == 0) {
	sprintf(s, "#<%s: destroyed>", cname);
    }
    else {
	sprintf(s, "#<%s: id=0x%x>", cname, get_gobject(self));
    }
    return rb_str_new2(s);
}

static VALUE
gobj_destroy(self)
    VALUE self;
{
    VALUE iv = rb_ivar_get(self, id_gtkdata);

    if (NIL_P(iv) || RDATA(iv)->data == 0) {
	/* destroyed object */
	return Qnil;
    }
    gtk_object_destroy(get_gobject(self));
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
    VALUE sig, data, args;
    ID id = 0;
    int i;

    rb_scan_args(argc, argv, "1*", &sig, &args);
    id = rb_intern(STR2CSTR(sig));
    data = rb_ary_new3(3, rb_f_lambda(), INT2NUM(id), args);
    add_relative(self, data);
    i = gtk_signal_connect_interp(GTK_OBJECT(get_widget(self)),
				  STR2CSTR(sig),
				  signal_callback, (gpointer)data,
				  NULL, 0);

    return INT2FIX(i);
}

static VALUE
gobj_sig_connect_after(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE sig, data, args;
    ID id = 0;
    int i;

    rb_scan_args(argc, argv, "1*", &sig, &args);
     id = rb_intern(STR2CSTR(sig));
    data = rb_ary_new3(3, rb_f_lambda(), INT2NUM(id), args);
    add_relative(self, data);
     i = gtk_signal_connect_interp(GTK_OBJECT(get_widget(self)),
				  STR2CSTR(sig),
				  signal_callback, (gpointer)data,
				  NULL, 1);

    return INT2FIX(i);
}

static VALUE
cont_bwidth(self, width)
    VALUE self, width;
{
    gtk_container_border_width(GTK_CONTAINER(get_widget(self)),
			       NUM2INT(width));
    return self;
}

static VALUE
cont_add(self, other)
    VALUE self, other;
{
    gtk_container_add(GTK_CONTAINER(get_widget(self)), get_widget(other));
    return self;
}

static VALUE
cont_disable_resize(self)
    VALUE self;
{
    gtk_container_disable_resize(GTK_CONTAINER(get_widget(self)));
    return self;
}

static VALUE
cont_enable_resize(self)
    VALUE self;
{
    gtk_container_enable_resize(GTK_CONTAINER(get_widget(self)));
    return self;
}

static VALUE
cont_block_resize(self)
    VALUE self;
{
    gtk_container_block_resize(GTK_CONTAINER(get_widget(self)));
    return self;
}

static VALUE
cont_unblock_resize(self)
    VALUE self;
{
    gtk_container_unblock_resize(GTK_CONTAINER(get_widget(self)));
    return self;
}

static VALUE
cont_need_resize(self)
    VALUE self;
{
    gtk_container_need_resize(GTK_CONTAINER(get_widget(self)));
    return self;
}

static VALUE
cont_foreach(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE callback;

    rb_scan_args(argc, argv, "01", &callback);
    if (NIL_P(callback)) {
	callback = rb_f_lambda();
    }
    gtk_container_foreach(GTK_CONTAINER(get_widget(self)), 
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
    gtk_container_foreach(GTK_CONTAINER(get_widget(self)), 
			  yield_callback, 0);
    return self;
}

static VALUE
cont_focus(self, direction)
    VALUE self, direction;
{
    gtk_container_focus(GTK_CONTAINER(get_widget(self)),
			(GtkDirectionType)NUM2INT(direction));
    return self;
}

static void
cont_children_callback(widget, data)
    GtkWidget *widget;
    gpointer data;
{
    VALUE ary = (VALUE)data;

    rb_ary_push(ary, get_value_from_gobject(GTK_OBJECT(widget)));
}

static VALUE
cont_children(self, direction)
    VALUE self, direction;
{
    VALUE ary = rb_ary_new();

    gtk_container_foreach(GTK_CONTAINER(get_widget(self)),
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
    gtk_alignment_set(GTK_ALIGNMENT(get_widget(self)),
		      NUM2DBL(xalign), NUM2DBL(yalign),
		      NUM2DBL(xscale), NUM2DBL(yscale));
    return self;
}

static VALUE
misc_set_align(self, xalign, yalign)
    VALUE self, xalign, yalign;
{
    gtk_misc_set_alignment(GTK_MISC(get_widget(self)),
		      NUM2DBL(xalign), NUM2DBL(yalign));
    return self;
}

static VALUE
misc_set_padding(self, xpad, ypad)
    VALUE self, xpad, ypad;
{
    gtk_misc_set_padding(GTK_MISC(get_widget(self)),
			 NUM2DBL(xpad), NUM2DBL(ypad));
    return self;
}

static VALUE
misc_get_xalign(self)
    VALUE self;
{
    return float_new(GTK_MISC(get_widget(self))->xalign);
}
static VALUE
misc_get_yalign(self)
    VALUE self;
{
    return float_new(GTK_MISC(get_widget(self))->yalign);
}
static VALUE
misc_get_xpad(self)
    VALUE self;
{
    return INT2NUM(GTK_MISC(get_widget(self))->xpad);
}
static VALUE
misc_get_ypad(self)
    VALUE self;
{
    return INT2NUM(GTK_MISC(get_widget(self))->ypad);
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
    gtk_arrow_set(GTK_ARROW(get_widget(self)),
		  (GtkArrowType)NUM2INT(arrow_t),
		  (GtkShadowType)NUM2INT(shadow_t));
    return self;
}

static VALUE
frame_initialize(self, label)
    VALUE self, label;
{
    set_widget(self, gtk_frame_new(NIL_P(label)?NULL:STR2CSTR(label)));
    return Qnil;
}

static VALUE
frame_set_label(self, label)
    VALUE self, label;
{
    gtk_frame_set_label(GTK_FRAME(get_widget(self)), STR2CSTR(label));
    return self;
}

static VALUE
frame_set_label_align(self, xalign, yalign)
    VALUE self, xalign, yalign;
{
    gtk_frame_set_label_align(GTK_FRAME(get_widget(self)),
			      NUM2DBL(xalign),
			      NUM2DBL(yalign));

    return self;
}

static VALUE
frame_set_shadow_type(self, type)
    VALUE self, type;
{
    gtk_frame_set_shadow_type(GTK_FRAME(get_widget(self)),
			      (GtkShadowType)NUM2INT(type));
    return self;
}

static VALUE
aframe_initialize(self, label, xalign, yalign, ratio, obey_child)
    VALUE self, label, xalign, yalign, ratio, obey_child;
{
    set_widget(self, gtk_aspect_frame_new(NIL_P(label)?NULL:STR2CSTR(label),
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
    gtk_aspect_frame_set(GTK_ASPECT_FRAME(get_widget(self)),
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
widget_draw(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE rect;

    rb_scan_args(argc, argv, "01", &rect);
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
    gtk_widget_size_request(get_widget(self), get_grequisition(req));
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
    int i = gtk_widget_event(get_widget(self), get_gdkevent(event));
    return NUM2INT(i);
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
widget_visible(self)
    VALUE self;
{
    if (GTK_WIDGET_VISIBLE(get_widget(self)))
	return Qtrue;
    return Qfalse;
}

static VALUE
widget_reparent(self, parent)
    VALUE self, parent;
{
    gtk_widget_reparent(get_widget(self), get_widget(parent));
    return self;
}
static VALUE
widget_mapped(self)
    VALUE self;
{
    if (GTK_WIDGET_MAPPED(get_widget(self)))
	return TRUE;
    return FALSE;
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
    int i = gtk_widget_intersect(get_widget(self),
				 get_gdkrectangle(area),
				 get_gdkrectangle(intersect));
    return NUM2INT(i);
}

static VALUE
widget_basic(self)
    VALUE self;
{
    int i = gtk_widget_basic(get_widget(self));
    return NUM2INT(i);
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
    
    return rb_str_new2(name);
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
    if (rb_obj_is_kind_of(type, rb_cClass)) {
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
    return rb_assoc_new(INT2FIX(x), INT2FIX(y));
}

static VALUE
widget_is_ancestor(self, ancestor)
    VALUE self, ancestor;
{
    if (gtk_widget_is_ancestor(get_widget(self), get_widget(ancestor))) {
	return Qtrue;
    }
    return Qfalse;
}

static VALUE
widget_is_child(self, child)
    VALUE self, child;
{
    if (gtk_widget_is_child(get_widget(self), get_widget(child))) {
	return Qtrue;
    }
    return Qfalse;
}

static VALUE
widget_get_events(self)
    VALUE self;
{
    int i = gtk_widget_get_events(get_widget(self));
    return NUM2INT(i);
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
widget_shape_combine_mask(self, gdk_pixmap_mask, x, y)
    VALUE self, gdk_pixmap_mask, x, y;
{
    gtk_widget_shape_combine_mask(get_widget(self),
				  get_gdkpixmap(gdk_pixmap_mask),
				  NUM2INT(x), NUM2INT(y));
    return self;
}

static VALUE
widget_get_alloc(self)
	VALUE self;
{
	return make_gallocation(&(get_widget(self)->allocation));
}

static VALUE
widget_get_requisition(self)
	VALUE self;
{
	return make_grequisition(&(get_widget(self)->requisition));
}

static VALUE
widget_set_requisition(self, w,h)
	VALUE self,w,h;
{
  GtkRequisition *r = &(get_widget(self)->requisition);
  r->width  = NUM2INT(w);
  r->height = NUM2INT(h);
  return self;
}

static VALUE
widget_state(self)
	VALUE self;
{
	return INT2FIX(get_widget(self)->state);
}

static VALUE
bbox_get_child_size_default(self)
    VALUE self;
{
    int min_width, max_width;

    gtk_button_box_get_child_size_default(&min_width, &max_width);

    return rb_assoc_new(INT2FIX(min_width), INT2FIX(max_width));
}

static VALUE
bbox_get_child_ipadding_default(self)
    VALUE self;
{
    int ipad_x, ipad_y;

    gtk_button_box_get_child_ipadding_default(&ipad_x, &ipad_y);
    return rb_assoc_new(INT2FIX(ipad_x), INT2FIX(ipad_y));
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
    int i = gtk_button_box_get_spacing(GTK_BUTTON_BOX(get_widget(self)));

    return INT2FIX(i);
}

static VALUE
bbox_get_layout(self)
    VALUE self;
{
    int i = gtk_button_box_get_layout(GTK_BUTTON_BOX(get_widget(self)));

    return INT2FIX(i);
}

static VALUE
bbox_get_child_size(self)
    VALUE self;
{
    int min_width, max_width;

    gtk_button_box_get_child_size(GTK_BUTTON_BOX(get_widget(self)),
				  &min_width, &max_width);
    return rb_assoc_new(INT2FIX(min_width), INT2FIX(max_width));
}

static VALUE
bbox_get_child_ipadding(self)
    VALUE self;
{
    int ipad_x, ipad_y;

    gtk_button_box_get_child_ipadding(GTK_BUTTON_BOX(get_widget(self)),
				      &ipad_x, &ipad_y);
    return rb_assoc_new(INT2FIX(ipad_x), INT2FIX(ipad_y));
}

static VALUE
bbox_set_spacing(self, spacing)
    VALUE self, spacing;
{
    gtk_button_box_set_spacing(GTK_BUTTON_BOX(get_widget(self)),
			       NUM2INT(spacing));
    return self;
}

static VALUE
bbox_set_layout(self, layout)
    VALUE self, layout;
{
    gtk_button_box_set_layout(GTK_BUTTON_BOX(get_widget(self)),
			      NUM2INT(layout));
    return self;
}

static VALUE
bbox_set_child_size(self, min_width, max_width)
    VALUE self, min_width, max_width;
{
    gtk_button_box_set_child_size(GTK_BUTTON_BOX(get_widget(self)),
				  NUM2INT(min_width),
				  NUM2INT(max_width));
    return self;
}

static VALUE
bbox_set_child_ipadding(self, ipad_x, ipad_y)
    VALUE self, ipad_x, ipad_y;
{
    gtk_button_box_set_child_ipadding(GTK_BUTTON_BOX(get_widget(self)),
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
	    buf[i] = STR2CSTR(RARRAY(titles)->ptr[i]);
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
    gtk_clist_set_border(GTK_CLIST(get_widget(self)),
			 (GtkShadowType)NUM2INT(border));
    return self;
}

static VALUE
clist_set_sel_mode(self, mode)
    VALUE self, mode;
{
    gtk_clist_set_selection_mode(GTK_CLIST(get_widget(self)),
				 (GtkSelectionMode)NUM2INT(mode));
    return self;
}

static VALUE
clist_set_policy(self, vpolicy, hpolicy)
    VALUE self, vpolicy, hpolicy;
{
    gtk_clist_set_policy(GTK_CLIST(get_widget(self)),
			 (GtkPolicyType)NUM2INT(vpolicy),
			 (GtkPolicyType)NUM2INT(hpolicy));
    return self;
}

static VALUE
clist_freeze(self)
    VALUE self;
{
    gtk_clist_freeze(GTK_CLIST(get_widget(self)));
    return self;
}

static VALUE
clist_thaw(self)
    VALUE self;
{
    gtk_clist_thaw(GTK_CLIST(get_widget(self)));
    return self;
}

static VALUE
clist_col_titles_show(self)
    VALUE self;
{
    gtk_clist_column_titles_show(GTK_CLIST(get_widget(self)));
    return self;
}

static VALUE
clist_col_titles_hide(self)
    VALUE self;
{
    gtk_clist_column_titles_hide(GTK_CLIST(get_widget(self)));
    return self;
}

static VALUE
clist_col_title_active(self, column)
    VALUE self, column;
{
    gtk_clist_column_title_active(GTK_CLIST(get_widget(self)),
				  NUM2INT(column));
    return self;
}

static VALUE
clist_col_title_passive(self, column)
    VALUE self, column;
{
    gtk_clist_column_title_passive(GTK_CLIST(get_widget(self)),
				   NUM2INT(column));
    return self;
}

static VALUE
clist_col_titles_active(self)
    VALUE self;
{
    gtk_clist_column_titles_active(GTK_CLIST(get_widget(self)));
    return self;
}

static VALUE
clist_col_titles_passive(self)
    VALUE self;
{
    gtk_clist_column_titles_passive(GTK_CLIST(get_widget(self)));
    return self;
}

static VALUE
clist_set_col_title(self, col, title)
    VALUE self, col, title;
{
    gtk_clist_set_column_title(GTK_CLIST(get_widget(self)),
			       NUM2INT(col),
			       STR2CSTR(title));
    return self;
}

static VALUE
clist_set_col_wigdet(self, col, win)
    VALUE self, col, win;
{
    gtk_clist_set_column_widget(GTK_CLIST(get_widget(self)),
				NUM2INT(col),
				get_widget(win));
    return self;
}

static VALUE
clist_set_col_just(self, col, just)
    VALUE self, col, just;
{
    gtk_clist_set_column_justification(GTK_CLIST(get_widget(self)),
				       NUM2INT(col),
				       (GtkJustification)NUM2INT(just));
    return self;
}

static VALUE
clist_set_col_width(self, col, width)
    VALUE self, col, width;
{
    gtk_clist_set_column_width(GTK_CLIST(get_widget(self)),
			       NUM2INT(col), NUM2INT(width));
    return self;
}

static VALUE
clist_set_row_height(self, height)
    VALUE self, height;
{
    gtk_clist_set_row_height(GTK_CLIST(get_widget(self)), NUM2INT(height));
    return self;
}

static VALUE
clist_moveto(self, row, col, row_align, col_align)
    VALUE self, row, col, row_align, col_align;
{
    gtk_clist_moveto(GTK_CLIST(get_widget(self)),
		     NUM2INT(row), NUM2INT(col),
		     NUM2INT(row_align), NUM2INT(col_align));
    return self;
}

static VALUE
clist_set_text(self, row, col, text)
    VALUE self, row, col, text;
{
    gtk_clist_set_text(GTK_CLIST(get_widget(self)),
		       NUM2INT(row), NUM2INT(col),
		       STR2CSTR(text));
    return self;
}

static VALUE
clist_set_pixmap(self, row, col, pixmap, mask)
    VALUE self, row, col, pixmap, mask;
{
    gtk_clist_set_pixmap(GTK_CLIST(get_widget(self)),
			 NUM2INT(row), NUM2INT(col),
			 get_gdkpixmap(pixmap),
			 (GdkBitmap*)get_gdkpixmap(mask));
    return self;
}

static VALUE
clist_set_pixtext(self, row, col, text, spacing, pixmap, mask)
    VALUE self, row, col, text, spacing, pixmap, mask;
{
    gtk_clist_set_pixtext(GTK_CLIST(get_widget(self)),
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
    gtk_clist_set_foreground(GTK_CLIST(get_widget(self)),
			     NUM2INT(row), get_gdkcolor(color));
    return self;
}

static VALUE
clist_set_background(self, row, color)
    VALUE self, row, color;
{
    gtk_clist_set_background(GTK_CLIST(get_widget(self)),
			     NUM2INT(row), get_gdkcolor(color));
    return self;
}

static VALUE
clist_set_shift(self, row, col, verticle, horizontal)
    VALUE self, row, col, verticle, horizontal;
{
    gtk_clist_set_shift(GTK_CLIST(get_widget(self)),
			NUM2INT(row), NUM2INT(col),
			NUM2INT(verticle), NUM2INT(horizontal));
    return self;
}

static VALUE
clist_append(self, text)
    VALUE self, text;
{
    char **buf;
    int i, len;

    Check_Type(text, T_ARRAY);
    len = GTK_CLIST(get_widget(self))->columns;
    if (len > RARRAY(text)->len) {
	rb_raise(rb_eArgError, "text too short");
    }
    buf = ALLOCA_N(char*, len);
    for (i=0; i<len; i++) {
	buf[i] = STR2CSTR(RARRAY(text)->ptr[i]);
    }
    i = gtk_clist_append(GTK_CLIST(get_widget(self)), buf);
    return INT2FIX(i);
}

static VALUE
clist_insert(self, row, text)
    VALUE self, row, text;
{
    char **buf;
    int i, len;

    Check_Type(text, T_ARRAY);
    len = GTK_CLIST(get_widget(self))->columns;
    if (len > RARRAY(text)->len) {
	rb_raise(rb_eArgError, "text too short");
    }
    buf = ALLOCA_N(char*, len);
    for (i=0; i<len; i++) {
	buf[i] = STR2CSTR(RARRAY(text)->ptr[i]);
    }
    gtk_clist_insert(GTK_CLIST(get_widget(self)), NUM2INT(row), buf);
    return self;
}

static VALUE
clist_remove(self, row)
    VALUE self, row;
{
    gtk_clist_remove(GTK_CLIST(get_widget(self)), NUM2INT(row));
    return self;
}

static VALUE
clist_set_row_data(self, row, data)
    VALUE self, row, data;
{
    add_relative(self, data);
    gtk_clist_set_row_data(GTK_CLIST(get_widget(self)),
			   NUM2INT(row), (gpointer)data);
    return self;
}

static VALUE
clist_get_row_data(self, row)
    VALUE self, row;
{
    return (VALUE)gtk_clist_get_row_data(GTK_CLIST(get_widget(self)),
					 NUM2INT(row));
}

static VALUE
clist_select_row(self, row, col)
    VALUE self, row, col;
{
    gtk_clist_select_row(GTK_CLIST(get_widget(self)),
			 NUM2INT(row), NUM2INT(col));
    return self;
}

static VALUE
clist_unselect_row(self, row, col)
    VALUE self, row, col;
{
    gtk_clist_unselect_row(GTK_CLIST(get_widget(self)),
			   NUM2INT(row), NUM2INT(col));
    return self;
}

static VALUE
clist_clear(self)
    VALUE self;
{
    gtk_clist_clear(GTK_CLIST(get_widget(self)));
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
    gtk_window_set_policy(GTK_WINDOW(get_widget(self)),
			  RTEST(shrink), RTEST(grow), RTEST(auto_shrink));
    return self;
}

static VALUE
gwin_set_title(self, title)
    VALUE self, title;
{
    gtk_window_set_title(GTK_WINDOW(get_widget(self)), STR2CSTR(title));
    return self;
}

static VALUE
gwin_position(self, pos)
    VALUE self, pos;
{
    gtk_window_position(GTK_WINDOW(get_widget(self)),
			(GtkWindowPosition)NUM2INT(pos));

    return self;
}

static VALUE
gwin_set_wmclass(self, wmclass1, wmclass2)
    VALUE self, wmclass1, wmclass2;
{
    gtk_window_set_wmclass(GTK_WINDOW(get_widget(self)),
			   NIL_P(wmclass1)?NULL:STR2CSTR(wmclass1),
			   NIL_P(wmclass2)?NULL:STR2CSTR(wmclass2));
    return self;
}

static VALUE
gwin_set_focus(self, win)
    VALUE self, win;
{
    gtk_window_set_focus(GTK_WINDOW(get_widget(self)), get_widget(win));
    return self;
}

static VALUE
gwin_set_default(self, win)
    VALUE self, win;
{
    gtk_window_set_default(GTK_WINDOW(get_widget(self)), get_widget(win));
    return self;
}

static VALUE
gwin_add_accel(self, accel)
    VALUE self, accel;
{
    gtk_window_add_accelerator_table(GTK_WINDOW(get_widget(self)),
				     get_gtkacceltbl(accel));
    return self;
}

static VALUE
gwin_rm_accel(self, accel)
    VALUE self, accel;
{
    gtk_window_remove_accelerator_table(GTK_WINDOW(get_widget(self)),
					get_gtkacceltbl(accel));
    return self;
}

static VALUE
gwin_grab_add(self)
     VALUE self;
{
  gtk_grab_add(get_widget(self));
  return self;
}

static VALUE
gwin_grab_remove(self)
     VALUE self;
{
  gtk_grab_remove(get_widget(self));
  return self;
}

static VALUE
gwin_shape_combine_mask(self, shape_mask, offset_x, offset_y)
     VALUE self, shape_mask, offset_x, offset_y;
{
  gtk_widget_shape_combine_mask(get_widget(self),
				get_gdkbitmap(shape_mask),
				NUM2INT(offset_x),
				NUM2INT(offset_y));
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
    gtk_file_selection_set_filename(GTK_FILE_SELECTION(get_widget(self)),
				    STR2CSTR(fname));

    return self;
}

static VALUE
fsel_get_fname(self)
    VALUE self;
{
    gchar *fname;

    fname = gtk_file_selection_get_filename(GTK_FILE_SELECTION(get_widget(self)));

    return rb_str_new2(fname);
}

static VALUE
fsel_ok_button(self)
    VALUE self;
{
    VALUE b = rb_iv_get(self, "ok_button");

    if (NIL_P(b)) {
	GtkWidget *w = GTK_FILE_SELECTION(get_widget(self))->ok_button;
	b = make_widget(gButton, w);
	rb_iv_set(self, "ok_button", b);
    }

    return b;
}

static VALUE
fsel_cancel_button(self)
    VALUE self;
{
    VALUE b = rb_iv_get(self, "cancel_button");

    if (NIL_P(b)) {
	GtkWidget *w = GTK_FILE_SELECTION(get_widget(self))->cancel_button;
	b = make_widget(gButton, w);
	rb_iv_set(self, "cancel_button", b);
    }

    return b;
}

static VALUE
fsel_help_button(self)
    VALUE self;
{
    VALUE b = rb_iv_get(self, "help_button");

    if (NIL_P(b)) {
	GtkWidget *w = GTK_FILE_SELECTION(get_widget(self))->help_button;
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
label_get_jtype(self)
    VALUE self;
{
  return(INT2FIX(GTK_LABEL(get_widget(self))->jtype));
}
static VALUE
label_set_jtype(self, jtype)
    VALUE self, jtype;
{
  GtkJustification j;
  j = (GtkJustification) NUM2INT(jtype);
  gtk_label_set_justify(GTK_LABEL(get_widget(self)), j);
  return self;
}

static VALUE
label_get(self)
     VALUE self;
{
  gchar** str;
  gtk_label_get(GTK_LABEL(get_widget(self)), str);
  return rb_str_new2(*str);
}

static VALUE
label_set(self, str)
     VALUE self, str;
{
     gtk_label_set(GTK_LABEL(get_widget(self)), STR2CSTR(str));
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
    gtk_list_set_selection_mode(GTK_LIST(get_widget(self)),
				(GtkSelectionMode)NUM2INT(mode));
    return self;
}

static VALUE
list_sel_mode(self)
    VALUE self;
{
    return INT2FIX(GTK_LIST(get_widget(self))->selection_mode);
}

static VALUE
list_selection(self)
    VALUE self;
{
    return glist2ary(GTK_LIST(get_widget(self))->selection);
}

static VALUE
list_insert_items(self, items, pos)
    VALUE self, items, pos;
{
    GList *glist;

    glist = ary2glist(items);

    gtk_list_insert_items(GTK_LIST(get_widget(self)), glist, NUM2INT(pos));
    g_list_free(glist);

    return self;
}

static VALUE
list_append_items(self, items)
    VALUE self, items;
{
    GList *glist;

    glist = ary2glist(items);

    gtk_list_append_items(GTK_LIST(get_widget(self)), glist);
    g_list_free(glist);

    return self;
}

static VALUE
list_prepend_items(self, items)
    VALUE self, items;
{
    GList *glist;

    glist = ary2glist(items);
    gtk_list_prepend_items(GTK_LIST(get_widget(self)), glist);
    g_list_free(glist);

    return self;
}

static VALUE
list_remove_items(self, items)
    VALUE self, items;
{
    GList *glist;

    glist = ary2glist(items);
    gtk_list_remove_items(GTK_LIST(get_widget(self)), glist);
    g_list_free(glist);

    return self;
}

static VALUE
list_clear_items(self, start, end)
    VALUE self, start, end;
{
    gtk_list_clear_items(GTK_LIST(get_widget(self)),
			 NUM2INT(start), NUM2INT(end));
    return self;
}

static VALUE
list_select_item(self, pos)
    VALUE self, pos;
{
    gtk_list_select_item(GTK_LIST(get_widget(self)), NUM2INT(pos));
    return self;
}

static VALUE
list_unselect_item(self, pos)
    VALUE self, pos;
{
    gtk_list_unselect_item(GTK_LIST(get_widget(self)), NUM2INT(pos));
    return self;
}

static VALUE
list_select_child(self, child)
    VALUE self, child;
{
    gtk_list_select_child(GTK_LIST(get_widget(self)), get_widget(child));
    return self;
}

static VALUE
list_unselect_child(self, child)
    VALUE self, child;
{
    gtk_list_unselect_child(GTK_LIST(get_widget(self)), get_widget(child));
    return self;
}

static VALUE
list_child_position(self, child)
    VALUE self, child;
{
    gint pos;

    pos = gtk_list_child_position(GTK_LIST(get_widget(self)),
				  get_widget(child));
    return INT2FIX(pos);
}

static VALUE
item_select(self)
    VALUE self;
{
    gtk_item_select(GTK_ITEM(get_widget(self)));
    return self;
}

static VALUE
item_deselect(self)
    VALUE self;
{
    gtk_item_deselect(GTK_ITEM(get_widget(self)));
    return self;
}

static VALUE
item_toggle(self)
    VALUE self;
{
    gtk_item_toggle(GTK_ITEM(get_widget(self)));
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
    gtk_menu_shell_append(GTK_MENU_SHELL(get_widget(self)),
			  get_widget(child));
    return self;
}

static VALUE
mshell_prepend(self, child)
    VALUE self, child;
{
    gtk_menu_shell_prepend(GTK_MENU_SHELL(get_widget(self)),
			   get_widget(child));
    return self;
}

static VALUE
mshell_insert(self, child, pos)
    VALUE self, child, pos;
{
    gtk_menu_shell_insert(GTK_MENU_SHELL(get_widget(self)),
			  get_widget(child),
			  NUM2INT(pos));
    return self;
}

static VALUE
mshell_deactivate(self)
    VALUE self;
{
    gtk_menu_shell_deactivate(GTK_MENU_SHELL(get_widget(self)));
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
    gtk_menu_append(GTK_MENU(get_widget(self)), get_widget(child));
    return self;
}

static VALUE
menu_prepend(self, child)
    VALUE self, child;
{
    gtk_menu_prepend(GTK_MENU(get_widget(self)), get_widget(child));
    return self;
}

static VALUE
menu_insert(self, child, pos)
    VALUE self, child, pos;
{
    gtk_menu_insert(GTK_MENU(get_widget(self)),
		    get_widget(child), NUM2INT(pos));
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
    GtkMenuPositionFunc pfunc = NULL;
    gpointer data = NULL;

    if (!NIL_P(func)) {
	pfunc = menu_pos_func;
	data = (gpointer)func;
	add_relative(self, func);
    }
    gtk_menu_popup(GTK_MENU(get_widget(self)),
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
    gtk_menu_popdown(GTK_MENU(get_widget(self)));
    return self;
}

static VALUE
menu_get_active(self)
    VALUE self;
{
    GtkWidget *mitem = gtk_menu_get_active(GTK_MENU(get_widget(self)));

    return make_gobject(gMenuItem, mitem);
}

static VALUE
menu_set_active(self, active)
    VALUE self, active;
{
    gtk_menu_set_active(GTK_MENU(get_widget(self)), NUM2INT(active));
    return self;
}

static VALUE
menu_set_acceltbl(self, table)
    VALUE self, table;
{
    gtk_menu_set_accelerator_table(GTK_MENU(get_widget(self)),
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
    gtk_menu_bar_append(GTK_MENU_BAR(get_widget(self)), get_widget(child));
    return self;
}

static VALUE
mbar_prepend(self, child)
    VALUE self, child;
{
    gtk_menu_bar_prepend(GTK_MENU_BAR(get_widget(self)), get_widget(child));
    return self;
}

static VALUE
mbar_insert(self, child, pos)
    VALUE self, child, pos;
{
    gtk_menu_bar_insert(GTK_MENU_BAR(get_widget(self)),
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
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(get_widget(self)),
			      get_widget(child));
    return self;
}

static VALUE
mitem_set_placement(self, place)
    VALUE self, place;
{
    gtk_menu_item_set_placement(GTK_MENU_ITEM(get_widget(self)), 
				(GtkSubmenuPlacement)NUM2INT(place));
    return self;
}

static VALUE
mitem_accelerator_size(self)
    VALUE self;
{
    gtk_menu_item_accelerator_size(GTK_MENU_ITEM(get_widget(self)));
    return self;
}

static VALUE
mitem_accelerator_text(self)
    VALUE self;
{
    char buf[1024];		/* enough? */

    gtk_menu_item_accelerator_text(GTK_MENU_ITEM(get_widget(self)), buf);
    return rb_str_new2(buf);
}

static VALUE
mitem_configure(self, show_toggle, show_submenu)
    VALUE self, show_toggle, show_submenu;
{
    gtk_menu_item_configure(GTK_MENU_ITEM(get_widget(self)), 
			    NUM2INT(show_toggle),
			    NUM2INT(show_submenu));
    return self;
}

static VALUE
mitem_select(self)
    VALUE self;
{
    gtk_menu_item_select(GTK_MENU_ITEM(get_widget(self)));
    return self;
}

static VALUE
mitem_deselect(self)
    VALUE self;
{
    gtk_menu_item_deselect(GTK_MENU_ITEM(get_widget(self)));
    return self;
}

static VALUE
mitem_activate(self)
    VALUE self;
{
    gtk_menu_item_activate(GTK_MENU_ITEM(get_widget(self)));
    return self;
}

static VALUE
mitem_right_justify(self)
    VALUE self;
{
    gtk_menu_item_right_justify(GTK_MENU_ITEM(get_widget(self)));
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
    gtk_check_menu_item_set_state(GTK_CHECK_MENU_ITEM(get_widget(self)), 
				  NUM2INT(state));
    return self;
}

static VALUE
cmitem_set_show_toggle(self, always)
    VALUE self, always;
{
    gtk_check_menu_item_set_show_toggle(GTK_CHECK_MENU_ITEM(get_widget(self)), 
					(gboolean)RTEST(always));
    return self;
}

static VALUE
cmitem_toggled(self)
    VALUE self;
{
    gtk_check_menu_item_toggled(GTK_CHECK_MENU_ITEM(get_widget(self)));
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
	    label = STR2CSTR(arg2);
	}
	if (rb_obj_is_kind_of(arg1, gRMenuItem)) {
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
    return gslist2ary(gtk_radio_menu_item_group(GTK_RADIO_MENU_ITEM(get_widget(self))));
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
    gtk_notebook_append_page(GTK_NOTEBOOK(get_widget(self)),
			     get_widget(child),
			     get_widget(label));
    return self;
}

static VALUE
note_prepend_page(self, child, label)
    VALUE self, child, label;
{
    gtk_notebook_prepend_page(GTK_NOTEBOOK(get_widget(self)),
			      get_widget(child),
			      get_widget(label));
    return self;
}

static VALUE
note_insert_page(self, child, label, pos)
    VALUE self, child, label, pos;
{
    gtk_notebook_insert_page(GTK_NOTEBOOK(get_widget(self)),
			     get_widget(child),
			     get_widget(label),
			     NUM2INT(pos));
    return self;
}

static VALUE
note_remove_page(self, pos)
    VALUE self, pos;
{
    gtk_notebook_remove_page(GTK_NOTEBOOK(get_widget(self)), NUM2INT(pos));
    return self;
}

static VALUE
note_set_page(self, pos)
    VALUE self, pos;
{
    gtk_notebook_set_page(GTK_NOTEBOOK(get_widget(self)), NUM2INT(pos));
    return self;
}

static VALUE
note_cur_page(self)
    VALUE self;
{
    return INT2FIX(GTK_NOTEBOOK(get_widget(self))->cur_page);
}

static VALUE
note_next_page(self)
    VALUE self;
{
    gtk_notebook_next_page(GTK_NOTEBOOK(get_widget(self)));
    return self;
}

static VALUE
note_prev_page(self)
    VALUE self;
{
    gtk_notebook_prev_page(GTK_NOTEBOOK(get_widget(self)));
    return self;
}

static VALUE
note_set_tab_pos(self, pos)
    VALUE self, pos;
{
    gtk_notebook_set_tab_pos(GTK_NOTEBOOK(get_widget(self)), NUM2INT(pos));
    return self;
}

static VALUE
note_tab_pos(self, pos)
    VALUE self, pos;
{
    return INT2FIX(GTK_NOTEBOOK(get_widget(self))->tab_pos);
}

static VALUE
note_set_show_tabs(self, show_tabs)
    VALUE self, show_tabs;
{
    gtk_notebook_set_tab_pos(GTK_NOTEBOOK(get_widget(self)), RTEST(show_tabs));
    return self;
}

static VALUE
note_show_tabs(self)
    VALUE self;
{
    return GTK_NOTEBOOK(get_widget(self))->show_tabs?Qtrue:Qfalse;
}

static VALUE
note_set_show_border(self, show_border)
    VALUE self, show_border;
{
    gtk_notebook_set_tab_pos(GTK_NOTEBOOK(get_widget(self)), RTEST(show_border));
    return self;
}

static VALUE
note_show_border(self)
    VALUE self;
{
    return GTK_NOTEBOOK(get_widget(self))->show_border?Qtrue:Qfalse;
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
    rb_iv_set(self, "option_menu", child);
    gtk_option_menu_set_menu(GTK_OPTION_MENU(get_widget(self)),
			     get_widget(child));
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
    gtk_option_menu_remove_menu(GTK_OPTION_MENU(get_widget(self)));
    return self;
}

static VALUE
omenu_set_history(self, index)
    VALUE self, index;
{
    gtk_option_menu_set_history(GTK_OPTION_MENU(get_widget(self)),
				NUM2INT(index));
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
    gtk_image_set(GTK_IMAGE(get_widget(self)), get_gdkimage(val),
		  get_gdkpixmap(mask));
    return self;
}

static VALUE
image_get(self)
    VALUE self;
{
    GdkImage  *val;
    GdkBitmap *mask;

    gtk_image_get(GTK_IMAGE(get_widget(self)), &val, &mask);

    return rb_assoc_new(make_gdkimage(self, val),
		     make_gdkpixmap(mask));
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
    gtk_preview_size(GTK_PREVIEW(get_widget(self)), NUM2INT(w), NUM2INT(h));
    return self;
}

static VALUE
preview_put(self, win, gc, srcx, srcy, dstx, dsty, w, h)
    VALUE self, win, gc, srcx, srcy, dstx, dsty, w, h;
{
    gtk_preview_put(GTK_PREVIEW(get_widget(self)), get_gdkwindow(win),
		    get_gdkgc(gc),
		    NUM2INT(srcx), NUM2INT(srcy),
		    NUM2INT(dstx), NUM2INT(dsty),
		    NUM2INT(w), NUM2INT(h));
    return self;
}

static VALUE
preview_put_row(self, src, dst, x, y, w)
    VALUE self, src, dst, x, y, w;
{
    int width = NUM2INT(w);
    int dlen = width;

    if (GTK_PREVIEW(get_widget(self))->type == GTK_PREVIEW_COLOR) {
	dlen *= 3;
    }
    Check_Type(src, T_STRING);
    if (RSTRING(src)->len < dlen) {
	rb_raise(rb_eArgError, "src too short");
    }
    Check_Type(dst, T_STRING);
    if (RSTRING(dst)->len < dlen) {
	rb_raise(rb_eArgError, "dst too short");
    }
    rb_str_modify(dst);
    gtk_preview_put_row(GTK_PREVIEW(get_widget(self)),
			RSTRING(src)->ptr, RSTRING(dst)->ptr,
			NUM2INT(x), NUM2INT(y), width);
    return self;
}

static VALUE
preview_draw_row(self, data, x, y, w)
    VALUE self, data, x, y, w;
{
    int width = NUM2INT(w);
    int dlen = width;

    if (GTK_PREVIEW(get_widget(self))->type == GTK_PREVIEW_COLOR) {
	dlen *= 3;
    }
    Check_Type(data, T_STRING);
    if (RSTRING(data)->len < dlen) {
	rb_raise(rb_eArgError, "data too short");
    }

    gtk_preview_draw_row(GTK_PREVIEW(get_widget(self)), RSTRING(data)->ptr,
			 NUM2INT(x), NUM2INT(y), width);
    return self;
}

static VALUE
preview_set_expand(self, expand)
    VALUE self, expand;
{
    gtk_preview_set_expand(GTK_PREVIEW(get_widget(self)), NUM2INT(expand));
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
    gtk_preview_set_install_cmap(RTEST(cmap));
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
    return make_gdkvisual(gtk_preview_get_visual());
}

static VALUE
preview_get_cmap(self)
    VALUE self;
{
    return make_gdkcmap(gtk_preview_get_cmap());
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
    gtk_progress_bar_update(GTK_PROGRESS_BAR(get_widget(self)),
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
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(get_widget(self)),
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

    gtk_table_attach(GTK_TABLE(get_widget(self)),
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
    gtk_table_set_row_spacing(GTK_TABLE(get_widget(self)),
			      NUM2INT(row), NUM2INT(spc));
    return self;
}

static VALUE
tbl_set_col_spacing(self, col, spc)
    VALUE self, col, spc;
{
    gtk_table_set_col_spacing(GTK_TABLE(get_widget(self)),
			      NUM2INT(col), NUM2INT(spc));
    return self;
}

static VALUE
tbl_set_row_spacings(self, spc)
    VALUE self, spc;
{
    gtk_table_set_row_spacings(GTK_TABLE(get_widget(self)), NUM2INT(spc));
    return self;
}

static VALUE
tbl_set_col_spacings(self, spc)
    VALUE self, spc;
{
    gtk_table_set_col_spacings(GTK_TABLE(get_widget(self)), NUM2INT(spc));
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
    gtk_text_set_editable(GTK_TEXT(get_widget(self)), RTEST(editable));
    return self;
}

static VALUE
txt_set_adjustment(self, h_adj, v_adj)
    VALUE self, h_adj, v_adj;
{
    gtk_text_set_adjustments(GTK_TEXT(get_widget(self)),
			     (GtkAdjustment*)get_gobject(h_adj),
			     (GtkAdjustment*)get_gobject(v_adj));

    return self;
}

static VALUE
txt_set_point(self, index)
    VALUE self, index;
{
    gtk_text_set_point(GTK_TEXT(get_widget(self)), NUM2INT(index));
    return self;
}

static VALUE
txt_get_point(self)
    VALUE self;
{
    int index = gtk_text_get_point(GTK_TEXT(get_widget(self)));
    
    return INT2FIX(index);
}

static VALUE
txt_get_length(self)
    VALUE self;
{
    int len = gtk_text_get_length(GTK_TEXT(get_widget(self)));
    
    return INT2FIX(len);
}

static VALUE
txt_freeze(self)
    VALUE self;
{
    gtk_text_freeze(GTK_TEXT(get_widget(self)));
    return self;
}

static VALUE
txt_thaw(self)
    VALUE self;
{
    gtk_text_thaw(GTK_TEXT(get_widget(self)));
    return self;
}

static VALUE
txt_insert(self, font, fore, back, str)
    VALUE self, font, fore, back, str;
{
    Check_Type(str, T_STRING);
    gtk_text_insert(GTK_TEXT(get_widget(self)), 
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
    gtk_text_backward_delete(GTK_TEXT(get_widget(self)), NUM2INT(nchars));
    return self;
}

static VALUE
txt_forward_delete(self, nchars)
    VALUE self, nchars;
{
    gtk_text_forward_delete(GTK_TEXT(get_widget(self)), NUM2INT(nchars));
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
tbar_append_item(self, text, ttext, ptext, icon, func)
    VALUE self, text, ttext, ptext, icon, func;
{
    if (NIL_P(func)) {
	func = rb_f_lambda();
    }
    gtk_toolbar_append_item(GTK_TOOLBAR(get_widget(self)),
			    NIL_P(text)?NULL:STR2CSTR(text),
			    NIL_P(ttext)?NULL:STR2CSTR(ttext),
			    NIL_P(ptext)?NULL:STR2CSTR(ptext),
			    get_widget(icon),
			    exec_callback,
			    (gpointer)func);
    return self;
}

static VALUE
tbar_prepend_item(self, text, ttext, ptext, icon, func)
    VALUE self, text, ttext, ptext, icon, func;
{
    if (NIL_P(func)) {
	func = rb_f_lambda();
    }
    gtk_toolbar_prepend_item(GTK_TOOLBAR(get_widget(self)),
			     NIL_P(text)?NULL:STR2CSTR(text),
			     NIL_P(ttext)?NULL:STR2CSTR(ttext),
			     NIL_P(ptext)?NULL:STR2CSTR(ptext),
			     get_widget(icon),
			     exec_callback,
			     (gpointer)func);
    return self;
}

static VALUE
tbar_insert_item(self, text, ttext, ptext, icon, func, pos)
    VALUE self, text, ttext, ptext, icon, func, pos;
{
    if (NIL_P(func)) {
	func = rb_f_lambda();
    }
    gtk_toolbar_insert_item(GTK_TOOLBAR(get_widget(self)),
			    NIL_P(text)?NULL:STR2CSTR(text),
			    NIL_P(ttext)?NULL:STR2CSTR(ttext),
			    NIL_P(ptext)?NULL:STR2CSTR(ptext),
			    get_widget(icon),
			    exec_callback,
			    (gpointer)func,
			    NUM2INT(pos));
    return self;
}

static VALUE
tbar_append_space(self)
    VALUE self;
{
    gtk_toolbar_append_space(GTK_TOOLBAR(get_widget(self)));
    return self;
}

static VALUE
tbar_prepend_space(self)
    VALUE self;
{
    gtk_toolbar_prepend_space(GTK_TOOLBAR(get_widget(self)));
    return self;
}

static VALUE
tbar_insert_space(self, pos)
    VALUE self, pos;
{
    gtk_toolbar_insert_space(GTK_TOOLBAR(get_widget(self)), NUM2INT(pos));
    return self;
}

static VALUE
tbar_set_orientation(self, orientation)
    VALUE self, orientation;
{
    gtk_toolbar_set_orientation(GTK_TOOLBAR(get_widget(self)), 
				(GtkOrientation)NUM2INT(orientation));
    return self;
}

static VALUE
tbar_set_style(self, style)
    VALUE self, style;
{
    gtk_toolbar_set_style(GTK_TOOLBAR(get_widget(self)), 
			  (GtkToolbarStyle)NUM2INT(style));
    return self;
}

static VALUE
tbar_set_space_size(self, size)
    VALUE self, size;
{
    gtk_toolbar_set_space_size(GTK_TOOLBAR(get_widget(self)), NUM2INT(size));
    return self;
}

static VALUE
tbar_set_tooltips(self, enable)
    VALUE self, enable;
{
    gtk_toolbar_set_tooltips(GTK_TOOLBAR(get_widget(self)), RTEST(enable));
    return self;
}

static VALUE
ttips_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_tooltips_new());
    return Qnil;
}

static VALUE
ttips_set_tip(self, win, text, priv)
    VALUE self, win, text, priv;
{
    gtk_tooltips_set_tip(GTK_TOOLTIPS(get_widget(self)),
			 get_widget(win),
			 NIL_P(text)?NULL:STR2CSTR(text),
			 NIL_P(priv)?NULL:STR2CSTR(priv));

    return self;
}

static VALUE
ttips_set_delay(self, delay)
    VALUE self, delay;
{
    gtk_tooltips_set_delay(GTK_TOOLTIPS(get_widget(self)), NUM2INT(delay));

    return self;
}

static VALUE
ttips_set_colors(self, back, fore)
    VALUE self, back, fore;
{
    gtk_tooltips_set_colors(GTK_TOOLTIPS(get_widget(self)),
			    get_gdkcolor(back),
			    get_gdkcolor(fore));
    return self;
}

static VALUE
ttips_enable(self)
    VALUE self;
{
    gtk_tooltips_enable(GTK_TOOLTIPS(get_widget(self)));
    return self;
}

static VALUE
ttips_disable(self)
    VALUE self;
{
    gtk_tooltips_disable(GTK_TOOLTIPS(get_widget(self)));
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
    gtk_tree_append(GTK_TREE(get_widget(self)), get_widget(child));
    return self;
}

static VALUE
tree_prepend(self, child)
    VALUE self, child;
{
    gtk_tree_prepend(GTK_TREE(get_widget(self)), get_widget(child));
    return self;
}

static VALUE
tree_insert(self, child, pos)
    VALUE self, child, pos;
{
    gtk_tree_insert(GTK_TREE(get_widget(self)), get_widget(child),
		    NUM2INT(pos));
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
	widget = gtk_tree_item_new_with_label(STR2CSTR(label));
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
    gtk_tree_item_set_subtree(GTK_TREE_ITEM(get_widget(self)),
			      get_widget(subtree));
    return self;
}

static VALUE
titem_select(self)
    VALUE self;
{
    gtk_tree_item_select(GTK_TREE_ITEM(get_widget(self)));
    return self;
}

static VALUE
titem_deselect(self)
    VALUE self;
{
    gtk_tree_item_deselect(GTK_TREE_ITEM(get_widget(self)));
    return self;
}

static VALUE
titem_expand(self)
    VALUE self;
{
    gtk_tree_item_expand(GTK_TREE_ITEM(get_widget(self)));
    return self;
}

static VALUE
titem_collapse(self)
    VALUE self;
{
    gtk_tree_item_collapse(GTK_TREE_ITEM(get_widget(self)));
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
    GtkAdjustment *adj = gtk_viewport_get_hadjustment(GTK_VIEWPORT(get_widget(self)));

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
    gtk_viewport_set_vadjustment(GTK_VIEWPORT(get_widget(self)),
				 GTK_ADJUSTMENT(get_gobject(adj)));

    return self;
}

static VALUE
vport_set_hadj(self, adj)
    VALUE self, adj;
{
    gtk_viewport_set_hadjustment(GTK_VIEWPORT(get_widget(self)),
				 GTK_ADJUSTMENT(get_gobject(adj)));

    return self;
}

static VALUE
vport_set_shadow(self, type)
    VALUE self, type;
{
    gtk_viewport_set_shadow_type(GTK_VIEWPORT(get_widget(self)),
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
	widget = gtk_button_new_with_label(STR2CSTR(label));
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
    gtk_button_pressed(GTK_BUTTON(get_widget(self)));
    return self;
}

static VALUE
button_released(self)
    VALUE self;
{
    gtk_button_released(GTK_BUTTON(get_widget(self)));
    return self;
}

static VALUE
button_clicked(self)
    VALUE self;
{
    gtk_button_clicked(GTK_BUTTON(get_widget(self)));
    return self;
}

static VALUE
button_enter(self)
    VALUE self;
{
    gtk_button_enter(GTK_BUTTON(get_widget(self)));
    return self;
}

static VALUE
button_leave(self)
    VALUE self;
{
    gtk_button_leave(GTK_BUTTON(get_widget(self)));
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
	widget = gtk_toggle_button_new_with_label(STR2CSTR(label));
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
    gtk_toggle_button_set_mode(GTK_TOGGLE_BUTTON(get_widget(self)),
			       NUM2INT(mode));
    return self;
}

static VALUE
tbtn_set_state(self, state)
    VALUE self, state;
{
    gtk_toggle_button_set_state(GTK_TOGGLE_BUTTON(get_widget(self)),
				NUM2INT(state));
    return self;
}

static VALUE
tbtn_toggled(self)
    VALUE self;
{
    gtk_toggle_button_toggled(GTK_TOGGLE_BUTTON(get_widget(self)));
    return self;
}

static VALUE
tbtn_active(self)
    VALUE self;
{
    if (GTK_TOGGLE_BUTTON(get_widget(self))->active)
	return Qtrue;
    return Qfalse;
}

static VALUE
cbtn_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
{
    VALUE label;
    GtkWidget *widget;

    if (rb_scan_args(argc, argv, "01", &label) == 1) {
	widget = gtk_check_button_new_with_label(STR2CSTR(label));
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
	    label = STR2CSTR(arg2);
	}
	if (rb_obj_is_kind_of(arg1, gRButton)) {
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

    expand = fill = Qtrue; padding = 0;
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
	gtk_box_pack_start(GTK_BOX(get_widget(self)), child, expand, fill, padding);
    else
	gtk_box_pack_end(GTK_BOX(get_widget(self)), child, expand, fill, padding);
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

    rb_scan_args(argc, argv, "02", &homogeneous, &spacing);

    set_widget(self, gtk_vbox_new(RTEST(homogeneous), NUM2INT(spacing)));
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
    gtk_color_selection_set_update_policy(GTK_COLOR_SELECTION(get_widget(self)),
					  (GtkUpdateType)NUM2INT(policy));
    return self;
}

static VALUE
colorsel_set_opacity(self, opacity)
    VALUE self, opacity;
{
    gtk_color_selection_set_opacity(GTK_COLOR_SELECTION(get_widget(self)),
				    RTEST(opacity));
    return self;
}

static VALUE
colorsel_set_color(self, color)
    VALUE self, color;
{
    double buf[3];

    Check_Type(color, T_ARRAY);
    if (RARRAY(color)->len < 3) {
	rb_raise(rb_eArgError, "color array too small");
    }
    buf[0] = NUM2DBL(RARRAY(color)->ptr[0]);
    buf[1] = NUM2DBL(RARRAY(color)->ptr[1]);
    buf[2] = NUM2DBL(RARRAY(color)->ptr[2]);

    gtk_color_selection_set_color(GTK_COLOR_SELECTION(get_widget(self)), buf);
    return self;
}

static VALUE
colorsel_get_color(self)
    VALUE self;
{
    double buf[3];
    VALUE ary;

    gtk_color_selection_get_color(GTK_COLOR_SELECTION(get_widget(self)), buf);
    ary = rb_ary_new2(3);
    rb_ary_push(ary, NUM2DBL(buf[0]));
    rb_ary_push(ary, NUM2DBL(buf[1]));
    rb_ary_push(ary, NUM2DBL(buf[2]));
    return ary;
}

static VALUE
cdialog_initialize(self, title)
    VALUE self;
{
    set_widget(self, gtk_color_selection_dialog_new(STR2CSTR(title)));
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
    gtk_pixmap_set(GTK_PIXMAP(get_widget(self)),
		   get_gdkpixmap(val), get_gdkpixmap(mask));
    return self;
}

static VALUE
pixmap_get(self)
    VALUE self;
{
    GdkPixmap  *val;
    GdkBitmap *mask;

    gtk_pixmap_get(GTK_PIXMAP(get_widget(self)), &val, &mask);

    return rb_assoc_new(make_gdkpixmap(val),
		     make_gdkbitmap(mask));
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
    gtk_drawing_area_size(GTK_DRAWING_AREA(get_widget(self)),
			  NUM2INT(w), NUM2INT(h));
    return self;
}

static VALUE
edit_sel_region(self, start, end)
    VALUE self, start, end;
{
    gtk_editable_select_region(GTK_EDITABLE(get_widget(self)),
			       NUM2INT(start), NUM2INT(end));
    return self;
}

static VALUE
edit_insert_text(self, new_text)
    VALUE self;
{
    gint pos;

    Check_Type(new_text, T_STRING);
    gtk_editable_insert_text(GTK_EDITABLE(get_widget(self)),
			     RSTRING(new_text)->ptr,
			     RSTRING(new_text)->len,
			     &pos);
    return INT2NUM(pos);
}

static VALUE
edit_delete_text(self, start, end)
    VALUE self, start, end;
{
    gtk_editable_delete_text(GTK_EDITABLE(get_widget(self)),
			     NUM2INT(start), NUM2INT(end));
    return self;
}

static VALUE
edit_get_chars(self, start, end)
    VALUE self, start, end;
{
    gchar *s;

    s = gtk_editable_get_chars(GTK_EDITABLE(get_widget(self)),
			       NUM2INT(start), NUM2INT(end));
    return rb_str_new2(s);
}

static VALUE
edit_cut_clipboard(self, time)
    VALUE self, time;
{
    gtk_editable_cut_clipboard(GTK_EDITABLE(get_widget(self)),NUM2INT(time));
    return self;
}

static VALUE
edit_copy_clipboard(self, time)
    VALUE self, time;
{
    gtk_editable_copy_clipboard(GTK_EDITABLE(get_widget(self)),NUM2INT(time));
    return self;
}
	
static VALUE
edit_paste_clipboard(self, time)
    VALUE self, time;
{
    gtk_editable_paste_clipboard(GTK_EDITABLE(get_widget(self)),NUM2INT(time));
    return self;
}
	
static VALUE
edit_claim_selection(self, claim, time)
    VALUE self, claim, time;
{
    gtk_editable_claim_selection(GTK_EDITABLE(get_widget(self)),
				 RTEST(claim), NUM2INT(time));
    return self;
}
	
static VALUE
edit_delete_selection(self)
    VALUE self;
{
    gtk_editable_delete_selection(GTK_EDITABLE(get_widget(self)));
    return self;
}

static VALUE
edit_changed(self)
    VALUE self;
{
    gtk_editable_changed(GTK_EDITABLE(get_widget(self)));
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
    gtk_entry_set_text(GTK_ENTRY(get_widget(self)), STR2CSTR(text));

    return self;
}

static VALUE
entry_append_text(self, text)
    VALUE self, text;
{
    gtk_entry_append_text(GTK_ENTRY(get_widget(self)), STR2CSTR(text));
    return self;
}

static VALUE
entry_prepend_text(self, text)
    VALUE self, text;
{
    gtk_entry_prepend_text(GTK_ENTRY(get_widget(self)), STR2CSTR(text));
    return self;
}

static VALUE
entry_set_position(self, position)
    VALUE self, position;
{
    gtk_entry_set_position(GTK_ENTRY(get_widget(self)), NUM2INT(position));
    return self;
}

static VALUE
entry_get_text(self)
    VALUE self;
{
    gchar* text;
    text = gtk_entry_get_text(GTK_ENTRY(get_widget(self)));
    return rb_str_new2(text);
}

static VALUE
entry_set_visibility(self, visibility)
    VALUE self, visibility;
{
    gtk_entry_set_visibility(GTK_ENTRY(get_widget(self)), RTEST(visibility));
    return self;
}

static VALUE
entry_set_editable(self, editable)
    VALUE self, editable;
{
    gtk_entry_set_editable(GTK_ENTRY(get_widget(self)), RTEST(editable));
    return self;
}

static VALUE
entry_set_max_length(self, max)
    VALUE self, max;
{
    gtk_entry_set_max_length(GTK_ENTRY(get_widget(self)), NUM2INT(max));
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
    gtk_fixed_put(GTK_FIXED(get_widget(self)), get_widget(win), NUM2INT(x), NUM2INT(y));
    return self;
}

static VALUE
fixed_move(self, win, x, y)
    VALUE self, win, x, y;
{
    gtk_fixed_move(GTK_FIXED(get_widget(self)), get_widget(win), NUM2INT(x), NUM2INT(y));
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
    return rb_float_new(GTK_GAMMA_CURVE(get_widget(self))->gamma);
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
    int i = gtk_hbutton_box_get_spacing_default();
    
    return INT2FIX(i);
}

static VALUE
hbbox_get_layout_default(self)
    VALUE self;
{
    int i = gtk_hbutton_box_get_layout_default();
    
    return INT2FIX(i);
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
    int i = gtk_vbutton_box_get_spacing_default();
    
    return INT2FIX(i);
}

static VALUE
vbbox_get_layout_default(self)
    VALUE self;
{
    int i = gtk_vbutton_box_get_layout_default();
    
    return INT2FIX(i);
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

    rb_scan_args(argc, argv, "02", &homogeneous, &spacing);

    set_widget(self, gtk_hbox_new(RTEST(homogeneous), NUM2INT(spacing)));
    return Qnil;
}

static VALUE
statusbar_initialize(self)
     VALUE self;
{
  set_widget(self, gtk_statusbar_new());
  return Qnil;
}

static VALUE
statusbar_push(self, id, text)
     VALUE self;
     VALUE id;
     VALUE text;
{
  gint message_id;
  message_id = gtk_statusbar_push(GTK_STATUSBAR(get_widget(self)), 
				  NUM2INT(id), STR2CSTR(text));
  return INT2FIX(message_id);
}

static VALUE
statusbar_pop(self, id)
     VALUE self;
     VALUE id;
{
  gtk_statusbar_pop(GTK_STATUSBAR(get_widget(self)), NUM2INT(id));
  return Qnil;

}

static VALUE
statusbar_get_context_id(self, text)
     VALUE self;
     VALUE text;
{
  gint context_id;
  context_id = gtk_statusbar_get_context_id(GTK_STATUSBAR(get_widget(self)),
					    STR2CSTR(text));
  return INT2FIX(context_id);
}

static VALUE
statusbar_remove(self, cid, mid)
     VALUE self;
     VALUE cid;
     VALUE mid;
{
  gtk_statusbar_remove(GTK_STATUSBAR(get_widget(self)),
		       NUM2INT(cid), NUM2INT(mid)); 
  return Qnil;
}

static VALUE
combo_initialize(self)
    VALUE self;
{
    set_widget(self, gtk_combo_new());
    return Qnil;
}

static VALUE
combo_val_in_list(self, val, ok)
    VALUE self, val, ok;
{
    gtk_combo_set_value_in_list(GTK_COMBO(get_widget(self)),
				RTEST(val), RTEST(ok));
    return Qnil;
}

static VALUE
combo_use_arrows(self, val)
    VALUE self, val;
{
    gtk_combo_set_use_arrows(GTK_COMBO(get_widget(self)),
			     RTEST(val));
    return Qnil;
}

static VALUE
combo_case_sensitive(self, val)
    VALUE self, val;
{
    gtk_combo_set_case_sensitive(GTK_COMBO(get_widget(self)),
				 RTEST(val));
    return Qnil;
}

static VALUE
combo_item_string(self, item, val)
    VALUE self, item, val;
{
    gtk_combo_set_item_string(GTK_COMBO(get_widget(self)),
			      GTK_ITEM(get_widget(self)),
			      NIL_P(val)?NULL:STR2CSTR(val));
    return Qnil;
}

static VALUE
combo_popdown_strings(self, ary)
    VALUE self, ary;
{
    int i;
    GList *glist = NULL;

    Check_Type(ary, T_ARRAY);
    for (i=0; i<RARRAY(ary)->len; i++) {
	/* check to avoid memory leak */
	STR2CSTR(RARRAY(ary)->ptr[i]);
    }
    for (i=0; i<RARRAY(ary)->len; i++) {
	glist = g_list_append(glist,STR2CSTR(RARRAY(ary)->ptr[i]));
    }

    gtk_combo_set_popdown_strings(GTK_COMBO(get_widget(self)), glist);
    return Qnil;
}

static VALUE
combo_disable_activate(self)
    VALUE self;
{
    gtk_combo_disable_activate(GTK_COMBO(get_widget(self)));
    return Qnil;
}

static VALUE
combo_entry(self)
    VALUE self;
{
    return make_widget(gEntry, GTK_COMBO(get_widget(self))->entry);
}

static VALUE
combo_button(self)
    VALUE self;
{
    return make_widget(gButton, GTK_COMBO(get_widget(self))->button);
}

static VALUE
combo_popup(self)
    VALUE self;
{
    return make_widget(gScrolledWin, GTK_COMBO(get_widget(self))->popup);
}

static VALUE
combo_popwin(self)
    VALUE self;
{
    return make_widget(gWindow, GTK_COMBO(get_widget(self))->popwin);
}

static VALUE
combo_list(self)
    VALUE self;
{
    return make_widget(gList, GTK_COMBO(get_widget(self))->list);
}

static VALUE
paned_add1(self, child)
    VALUE self, child;
{
    gtk_paned_add1(GTK_PANED(get_widget(self)), get_widget(child));
    return self;
}

static VALUE
paned_add2(self, child)
    VALUE self, child;
{
    gtk_paned_add2(GTK_PANED(get_widget(self)), get_widget(child));
    return self;
}

static VALUE
paned_handle_size(self, size)
    VALUE self, size;
{
    gtk_paned_handle_size(GTK_PANED(get_widget(self)), NUM2INT(size));
    return self;
}

static VALUE
paned_gutter_size(self, size)
    VALUE self, size;
{
    gtk_paned_gutter_size(GTK_PANED(get_widget(self)), NUM2INT(size));
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
    gtk_ruler_set_metric(GTK_RULER(get_widget(self)), 
			 (GtkMetricType)NUM2INT(metric));

    return self;
}

static VALUE
ruler_set_range(self, lower, upper, position, max_size)
    VALUE self, lower, upper, position, max_size;
{
    gtk_ruler_set_range(GTK_RULER(get_widget(self)), 
			NUM2DBL(lower), NUM2DBL(upper),
			NUM2DBL(position), NUM2DBL(max_size));

    return self;
}

static VALUE
ruler_draw_ticks(self)
    VALUE self;
{
    gtk_ruler_draw_ticks(GTK_RULER(get_widget(self)));
    return self;
}

static VALUE
ruler_draw_pos(self)
    VALUE self;
{
    gtk_ruler_draw_pos(GTK_RULER(get_widget(self)));
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
    gtk_range_set_update_policy(GTK_RANGE(get_widget(self)),
				(GtkUpdateType)NUM2INT(policy));
    return self;
}

static VALUE
range_set_adj(self, adj)
    VALUE self, adj;
{
    gtk_range_set_adjustment(GTK_RANGE(get_widget(self)),
			     GTK_ADJUSTMENT(get_gobject(adj)));

    return self;
}

static VALUE
range_draw_bg(self)
    VALUE self;
{
    gtk_range_draw_background(GTK_RANGE(get_widget(self)));
    return self;
}

static VALUE
range_draw_trough(self)
    VALUE self;
{
    gtk_range_draw_trough(GTK_RANGE(get_widget(self)));
    return self;
}

static VALUE
range_draw_slider(self)
    VALUE self;
{
    gtk_range_draw_slider(GTK_RANGE(get_widget(self)));
    return self;
}

static VALUE
range_draw_step_forw(self)
    VALUE self;
{
    gtk_range_draw_step_forw(GTK_RANGE(get_widget(self)));
    return self;
}

static VALUE
range_draw_step_back(self)
    VALUE self;
{
    gtk_range_draw_step_back(GTK_RANGE(get_widget(self)));
    return self;
}

static VALUE
range_slider_update(self)
    VALUE self;
{
    gtk_range_slider_update(GTK_RANGE(get_widget(self)));
    return self;
}

static VALUE
range_trough_click(self, x, y)
    VALUE self, x, y;
{
    int i;

    i = gtk_range_trough_click(GTK_RANGE(get_widget(self)),
			       NUM2INT(x), NUM2INT(y),
			       0);
    return INT2FIX(i);
}

static VALUE
range_default_hslider_update(self)
    VALUE self;
{
    gtk_range_default_hslider_update(GTK_RANGE(get_widget(self)));
    return self;
}

static VALUE
range_default_vslider_update(self)
    VALUE self;
{
    gtk_range_default_vslider_update(GTK_RANGE(get_widget(self)));
    return self;
}

static VALUE
range_default_htrough_click(self, x, y)
    VALUE self, x, y;
{
    int i;

    i = gtk_range_default_htrough_click(GTK_RANGE(get_widget(self)),
					NUM2INT(x), NUM2INT(y),
					0);
    return INT2FIX(i);
}

static VALUE
range_default_vtrough_click(self, x, y, jump_prec)
    VALUE self, x, y, jump_prec;
{
    int i;

    i = gtk_range_default_vtrough_click(GTK_RANGE(get_widget(self)),
					NUM2INT(x), NUM2INT(y),
					0);
    return INT2FIX(i);
}

static VALUE
range_default_hmotion(self, xdelta, ydelta)
    VALUE self, xdelta, ydelta;
{
    gtk_range_default_hmotion(GTK_RANGE(get_widget(self)),
			      NUM2INT(xdelta), NUM2INT(ydelta));
    return self;
}

static VALUE
range_default_vmotion(self, xdelta, ydelta)
    VALUE self, xdelta, ydelta;
{
    gtk_range_default_vmotion(GTK_RANGE(get_widget(self)),
			      NUM2INT(xdelta), NUM2INT(ydelta));
    return self;
}

static VALUE
scale_set_digits(self, digits)
    VALUE self, digits;
{
    gtk_scale_set_digits(GTK_SCALE(get_widget(self)), NUM2INT(digits));
    return self;
}

static VALUE
scale_set_draw_value(self, draw_value)
    VALUE self, draw_value;
{
    gtk_scale_set_draw_value(GTK_SCALE(get_widget(self)),
			     NUM2INT(draw_value));
    return self;
}

static VALUE
scale_set_value_pos(self, pos)
    VALUE self, pos;
{
    gtk_scale_set_value_pos(GTK_SCALE(get_widget(self)), 
			    (GtkPositionType)NUM2INT(pos));
    return self;
}

static VALUE
scale_value_width(self)
    VALUE self;
{
    int i = gtk_scale_value_width(GTK_SCALE(get_widget(self)));

    return INT2FIX(i);
}

static VALUE
scale_draw_value(self)
    VALUE self;
{
    gtk_scale_draw_value(GTK_SCALE(get_widget(self)));
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
style_s_new(klass)
    VALUE klass;
{
    return make_gstyle(gtk_style_new());
}

static VALUE
style_copy(self)
    VALUE self;
{
  return make_gstyle(gtk_style_copy(get_gstyle(self)));
}

static VALUE
style_attach(self, win)
    VALUE self, win;
{
    return make_gstyle(gtk_style_attach(get_gstyle(self), get_gdkwindow(win)));
}

static VALUE
style_detach(self)
{
    gtk_style_detach(get_gstyle(self));
    return self;
}

static VALUE
style_set_background(self, win, state_type)
    VALUE self, win, state_type;
{
    gtk_style_set_background(get_gstyle(self), get_gdkwindow(win),
			     (GtkStateType)NUM2INT(state_type));
    return self;
}

static VALUE
style_fg(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkcolor(get_gstyle(self)->fg[i]);
}

static VALUE
style_bg(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkcolor(get_gstyle(self)->bg[i]);
}

static VALUE
style_light(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkcolor(get_gstyle(self)->light[i]);
}

static VALUE
style_dark(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkcolor(get_gstyle(self)->dark[i]);
}

static VALUE
style_mid(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkcolor(get_gstyle(self)->mid[i]);
}

static VALUE
style_text(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkcolor(get_gstyle(self)->text[i]);
}

static VALUE
style_base(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkcolor(get_gstyle(self)->base[i]);
}

#define DEFINE_STYLE_SET_COLOR(FUNC, TYPE) \
static VALUE \
FUNC(self, idx, r, g, b) \
    VALUE self, idx, r, g, b; \
{ \
  GtkStyle *style; \
  GdkColor *color; \
  int i = NUM2INT(idx); \
 \
  if (i < 0 || 5 < i) ArgError("state out of range"); \
  style = get_gstyle(self); \
  if (style->fg_gc[0] != NULL) ArgError("you must not change widget style."); \
  color =  &(style-> TYPE [i]); \
  color->red   = NUM2INT(r); \
  color->green = NUM2INT(g); \
  color->blue  = NUM2INT(b); \
  return(make_gdkcolor(*color)); \
} \

DEFINE_STYLE_SET_COLOR(style_set_fg, fg)
DEFINE_STYLE_SET_COLOR(style_set_bg, bg)
DEFINE_STYLE_SET_COLOR(style_set_light, light)
DEFINE_STYLE_SET_COLOR(style_set_dark, dark)
DEFINE_STYLE_SET_COLOR(style_set_mid, mid)
DEFINE_STYLE_SET_COLOR(style_set_text, text)
DEFINE_STYLE_SET_COLOR(style_set_base, base)

static VALUE
style_black(self)
{
    return make_gdkcolor(get_gstyle(self)->black);
}

static VALUE
style_white(self)
{
    return make_gdkcolor(get_gstyle(self)->white);
}

static VALUE
style_font(self)
{
    return make_gdkfont(get_gstyle(self)->font);
}

static VALUE
style_set_font(self, f)
	 VALUE f;
{
  GdkFont *font = get_gdkfont(f);
  GtkStyle *style = get_gstyle(self);

  if (style->fg_gc[0] != NULL) ArgError("you must not change widget style.");
  if (style->font != NULL)
	gdk_font_unref(style->font);

  gdk_font_ref(font);
  style->font = font;

  return self;
}

static VALUE
style_fg_gc(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkgc(get_gstyle(self)->fg_gc[i]);
}

static VALUE
style_bg_gc(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkgc(get_gstyle(self)->bg_gc[i]);
}

static VALUE
style_light_gc(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkgc(get_gstyle(self)->light_gc[i]);
}

static VALUE
style_dark_gc(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkgc(get_gstyle(self)->dark_gc[i]);
}

static VALUE
style_mid_gc(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkgc(get_gstyle(self)->mid_gc[i]);
}

static VALUE
style_text_gc(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkgc(get_gstyle(self)->text_gc[i]);
}

static VALUE
style_base_gc(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkgc(get_gstyle(self)->base_gc[i]);
}

static VALUE
style_black_gc(self)
{
    return make_gdkgc(get_gstyle(self)->black_gc);
}

static VALUE
style_white_gc(self)
{
    return make_gdkgc(get_gstyle(self)->white_gc);
}

static VALUE
style_bg_pixmap(self, idx)
    VALUE self, idx;
{
    int i = NUM2INT(idx);

    if (i < 0 || 5 < i) rb_raise(rb_eArgError, "state out of range");
    return make_gdkpixmap(get_gstyle(self)->bg_pixmap[i]);
}


#if 0
static VALUE
style_draw_hline(self, win, state_type, x1, x2, y)
    VALUE self, win, type, x1, x2, y;
{
    gtk_draw_hline(get_gstyle(self), get_gdkwindow(win),
		   (GtkStateType)NUM2INT(state_type),
		   NUM2INT(x1), NUM2INT(x2), NUM2INT(y));
    return self;
}

static VALUE
style_draw_vline(self, win, state_type, y1, y2, x)
    VALUE self,win,type,y1,y2,x;
{
    gtk_draw_vline(get_gstyle(self), get_gdkwindow(win),
		   (GtkStateType)NUM2INT(state_type),
		   NUM2INT(y1), NUM2INT(y2), NUM2INT(x));
    return self;
}

static VALUE
style_draw_shadow(self,win,state_type,shadow_type,x,y,w,h)
    VALUE self,win,state_type,shadow_type,x,y,w,h;
{
    gtk_draw_shadow(get_gstyle(self), get_gdkwindow(win),
		    (GtkStateType)NUM2INT(state_type),
		    (GtkShadowType)NUM2INT(shadow_type),
		    NUM2INT(x), NUM2INT(y), 
		    NUM2INT(w), NUM2INT(h));
    return self;
}

static VALUE
style_draw_polygon(self,win,state_type,shadow_type,pnts,fill)
    VALUE self,win,state_type,shadow_type,pnts,fill;
{
    GdkPoint *points;
    int i;

    Check_Type(pnts, T_ARRAY);
    points = ALLOCA_N(GdkPoint,RARRAY(pnts)->len);
    for (i=0; i<RARRAY(pnts)->len; i++) {
	Check_Type(RARRAY(pnts)->ptr[i], T_ARRAY);
	if (RARRAY(RARRAY(pnts)->ptr[i])->len < 2) {
	    rb_raise(rb_eArgError, "point %d should be array of size 2", i);
	}
	points[i].x = NUM2INT(RARRAY(RARRAY(pnts)->ptr[i])->ptr[0]);
	points[i].y = NUM2INT(RARRAY(RARRAY(pnts)->ptr[i])->ptr[1]);
    }

    gtk_draw_polygon(get_gstyle(self), get_gdkwindow(win),
		     (GtkStateType)NUM2INT(state_type),
		     (GtkShadowType)NUM2INT(shadow_type),
		     points, RARRAY(pnts)->len,
		     RTEST(fill));
    return self;
}

static VALUE
style_draw_arrow(self,)		/* 9 */
{
    gtk_draw_polygon(get_gstyle(self), get_gdkwindow(win),
		     (GtkStateType)NUM2INT(state_type),
		     (GtkShadowType)NUM2INT(shadow_type),
		     points, RARRAY(pnts)->len,
		     RTEST(fill));
    return self;
}

static VALUE
style_draw_diamond(self,)	/* 7 */
{
}

static VALUE
style_draw_oval(self,)		/* 7 */
{
}

static VALUE
style_draw_string(self,)	/* 5 */
{
}
#endif

static VALUE
gallocation_x(self)
{
	return INT2NUM(get_gallocation(self)->x);
}

static VALUE
gallocation_y(self)
{
	return INT2NUM(get_gallocation(self)->y);
}

static VALUE
gallocation_w(self)
{
	return INT2NUM(get_gallocation(self)->width);
}

static VALUE
gallocation_h(self)
{
	return INT2NUM(get_gallocation(self)->height);
}

static VALUE
grequisition_w(self)
{
	return INT2NUM(get_grequisition(self)->width);
}
static VALUE
grequisition_h(self)
{
	return INT2NUM(get_grequisition(self)->height);
}
/*
static VALUE
grequisition_set_w(self, w)
	 VALUE self, w;
{
  get_grequisition(self)->width = NUM2INT(w);
  return self;
}
static VALUE
grequisition_set_h(self, h)
	 VALUE self, h;
{
  get_grequisition(self)->height = NUM2INT(h);
  return self;
}
*/

static VALUE
gtk_m_main(self)
    VALUE self;
{
    gtk_main();
    return Qnil;
}

static VALUE
gtk_rc_m_parse(self, rc)
    VALUE self, rc;
{
    gtk_rc_parse(STR2CSTR(rc));
    return Qnil;
}

static VALUE
gtk_rc_m_parse_string(self, rc)
    VALUE self, rc;
{
    gtk_rc_parse_string(STR2CSTR(rc));
    return Qnil;
}

static VALUE
gtk_rc_m_get_style(self, w)
    VALUE self, w;
{
    GtkStyle *s = gtk_rc_get_style(get_widget(w));
    return make_gstyle(s);
}

static VALUE
gtk_rc_m_add_widget_name_style(self, style, pat)
    VALUE self, style, pat;
{
    gtk_rc_add_widget_name_style(get_gstyle(style), STR2CSTR(pat));
    return Qnil;
}

static VALUE
gtk_rc_m_add_widget_class_style(self, style, pat)
    VALUE self, style, pat;
{
    gtk_rc_add_widget_class_style(get_gstyle(style), STR2CSTR(pat));
    return Qnil;
}

static VALUE
gdkdraw_draw_point(self, gc, x, y)
    VALUE self, gc, x, y;
{
    gdk_draw_point(get_gdkdrawable(self), get_gdkgc(gc),
		   NUM2INT(x), NUM2INT(y));
    return self;
}

static VALUE
gdkdraw_draw_line(self, gc, x1, y1, x2, y2)
    VALUE self, gc, x1, y1, x2, y2;
{
    gdk_draw_line(get_gdkdrawable(self), get_gdkgc(gc),
		  NUM2INT(x1), NUM2INT(y1),
		  NUM2INT(x2), NUM2INT(y2));
    return self;
}

static VALUE
gdkdraw_draw_rect(self, gc, filled, x, y, w, h)
    VALUE self, gc, filled, x, y, w, h;
{
    gdk_draw_rectangle(get_gdkdrawable(self), get_gdkgc(gc),
		       RTEST(filled),
		       NUM2INT(x), NUM2INT(y),
		       NUM2INT(w), NUM2INT(h));
    return self;
}

static VALUE
gdkdraw_draw_arc(self, gc, filled, x, y, w, h, a1, a2)
    VALUE gc, filled, x, y, w, h, a1, a2;
{
    gdk_draw_arc(get_gdkdrawable(self), get_gdkgc(gc),
		 RTEST(filled),
		 NUM2INT(x), NUM2INT(y),
		 NUM2INT(w), NUM2INT(h),
		 NUM2INT(a1), NUM2INT(a2));
    return self;
}

static VALUE
gdkdraw_draw_poly(self, gc, filled, pnts)
    VALUE self, gc, filled, pnts;
{
    GdkPoint *points;
    int i;

    Check_Type(pnts, T_ARRAY);
    points = ALLOCA_N(GdkPoint,RARRAY(pnts)->len);
    for (i=0; i<RARRAY(pnts)->len; i++) {
	Check_Type(RARRAY(pnts)->ptr[i], T_ARRAY);
	if (RARRAY(RARRAY(pnts)->ptr[i])->len < 2) {
	    rb_raise(rb_eArgError, "point %d should be array of size 2", i);
	}
	points[i].x = NUM2INT(RARRAY(RARRAY(pnts)->ptr[i])->ptr[0]);
	points[i].y = NUM2INT(RARRAY(RARRAY(pnts)->ptr[i])->ptr[1]);
    }
    gdk_draw_polygon(get_gdkdrawable(self), get_gdkgc(gc),
		     RTEST(filled),
		     points,
		     RARRAY(pnts)->len);
    return self;
}

static VALUE
gdkdraw_draw_text(self, font, gc, x, y, str)
    VALUE self, font, gc, x, y, str;
{
    Check_Type(str, T_STRING);
    gdk_draw_text(get_gdkdrawable(self), get_gdkfont(font), get_gdkgc(gc),
		  NUM2INT(x), NUM2INT(y),
		  RSTRING(str)->ptr, RSTRING(str)->len);
    return self;
}

static VALUE
gdkdraw_draw_pmap(self, gc, src, xsrc, ysrc, xdst, ydst, w, h)
    VALUE self, gc, src, xsrc, ysrc, xdst, ydst, w, h;
{
    gdk_draw_pixmap(get_gdkdrawable(self), get_gdkgc(gc),
		    get_gdkdrawable(src),
		    NUM2INT(xsrc), NUM2INT(ysrc),
		    NUM2INT(xdst), NUM2INT(ydst),
		    NUM2INT(w), NUM2INT(h));
    return self;
}

static VALUE
gdkdraw_draw_bmap(self, gc, src, xsrc, ysrc, xdst, ydst, w, h)
    VALUE self, gc, src, xsrc, ysrc, xdst, ydst, w, h;
{
    /* why there's no gdk_draw_bitmap()?? */
    gdk_draw_pixmap(get_gdkdrawable(self), get_gdkgc(gc),
		    get_gdkdrawable(src),
		    NUM2INT(xsrc), NUM2INT(ysrc),
		    NUM2INT(xdst), NUM2INT(ydst),
		    NUM2INT(w), NUM2INT(h));
    return self;
}

static VALUE
gdkdraw_draw_image(self, gc, image, xsrc, ysrc, xdst, ydst, w, h)
    VALUE self, gc, image, xsrc, ysrc, xdst, ydst, w, h;
{
    gdk_draw_image(get_gdkdrawable(self), get_gdkgc(gc),
		   get_gdkimage(image),
		   NUM2INT(xsrc), NUM2INT(ysrc),
		   NUM2INT(xdst), NUM2INT(ydst),
		   NUM2INT(w), NUM2INT(h));
    return self;
}

static VALUE
gdkdraw_draw_pnts(self, gc, pnts)
    VALUE self, gc, pnts;
{
    GdkPoint *points;
    int i;

    Check_Type(pnts, T_ARRAY);
    points = ALLOCA_N(GdkPoint,RARRAY(pnts)->len);
    for (i=0; i<RARRAY(pnts)->len; i++) {
	Check_Type(RARRAY(pnts)->ptr[i], T_ARRAY);
	if (RARRAY(RARRAY(pnts)->ptr[i])->len < 2) {
	    rb_raise(rb_eArgError, "point %d should be array of size 2", i);
	}
	points[i].x = NUM2INT(RARRAY(RARRAY(pnts)->ptr[i])->ptr[0]);
	points[i].y = NUM2INT(RARRAY(RARRAY(pnts)->ptr[i])->ptr[1]);
    }
    gdk_draw_points(get_gdkdrawable(self), get_gdkgc(gc),
		    points,
		    RARRAY(pnts)->len);
    return self;
}

static VALUE
gdkdraw_draw_segs(self, gc, segs)
    VALUE self, gc, segs;
{
    GdkSegment *segments;
    int i;

    Check_Type(segs, T_ARRAY);
    segments = ALLOCA_N(GdkSegment,RARRAY(segs)->len);
    for (i=0; i<RARRAY(segs)->len; i++) {
	Check_Type(RARRAY(segs)->ptr[i], T_ARRAY);
	if (RARRAY(RARRAY(segs)->ptr[i])->len < 4) {
	    rb_raise(rb_eArgError, "segment %d should be array of size 4", i);
	}
	segments[i].x1 = NUM2INT(RARRAY(RARRAY(segs)->ptr[i])->ptr[0]);
	segments[i].y1 = NUM2INT(RARRAY(RARRAY(segs)->ptr[i])->ptr[1]);
	segments[i].x2 = NUM2INT(RARRAY(RARRAY(segs)->ptr[i])->ptr[2]);
	segments[i].y2 = NUM2INT(RARRAY(RARRAY(segs)->ptr[i])->ptr[3]);
    }
    gdk_draw_segments(get_gdkdrawable(self), get_gdkgc(gc),
		      segments,
		      RARRAY(segs)->len);
    return self;
}


static VALUE
gdkrect_s_new(self, x, y, width, height)
	VALUE self, x, y, width, height;
{
	GdkRectangle new;
	new.x = NUM2INT(x);
	new.y = NUM2INT(y);
	new.width = NUM2INT(width);
	new.height = NUM2INT(height);
	return make_gdkrectangle(&new);
}

static VALUE
gdkrect_x(self)
{
	return INT2NUM(get_gdkrectangle(self)->x);
}

static VALUE
gdkrect_y(self)
{
	return INT2NUM(get_gdkrectangle(self)->y);
}

static VALUE
gdkrect_w(self)
{
	return INT2NUM(get_gdkrectangle(self)->width);
}

static VALUE
gdkrect_h(self)
{
	return INT2NUM(get_gdkrectangle(self)->height);
}

static VALUE
gdkevent_type(self)
{
  return INT2NUM(get_gdkevent(self)->type);
}

static VALUE
gdkeventexpose_area(self)
{
  return make_gdkrectangle( &(((GdkEventExpose*)get_gdkevent(self))->area) );
}

static VALUE
gdkeventbutton_x(self)
{
  return INT2NUM(((GdkEventButton*)get_gdkevent(self))->x);
}

static VALUE
gdkeventbutton_y(self)
{
  return INT2NUM(((GdkEventButton*)get_gdkevent(self))->y);
}

static VALUE
gdkeventbutton_button(self)
{
  return INT2NUM(((GdkEventButton*)get_gdkevent(self))->button);
}

static VALUE
gdkeventmotion_window(self)
{
  return make_gdkwindow( ((GdkEventMotion*)get_gdkevent(self))->window);
}

static VALUE
gdkeventmotion_x(self)
{
  return INT2NUM(((GdkEventMotion*)get_gdkevent(self))->x);
}

static VALUE
gdkeventmotion_y(self)
{
  return INT2NUM(((GdkEventMotion*)get_gdkevent(self))->y);
}

static VALUE
gdkeventmotion_state(self)
{
  return INT2NUM(((GdkEventMotion*)get_gdkevent(self))->state);
}

static VALUE
gdkeventmotion_is_hint(self)
{
  return INT2NUM(((GdkEventMotion*)get_gdkevent(self))->is_hint);
}


static gint
idle()
{
    CHECK_INTS;
#ifdef THREAD
    if (!rb_thread_critical) rb_thread_schedule();
#endif
    return Qtrue;
}

static void
exec_interval(proc)
    VALUE proc;
{
    rb_funcall(proc, id_call, 0);
}

static VALUE
timeout_add(self, interval)
    VALUE self, interval;
{
    int id;

    id = gtk_timeout_add_interp(NUM2INT(interval), exec_interval,
				(gpointer)rb_f_lambda(), 0);
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
idle_add(self)
    VALUE self;
{
    int id;

    id = gtk_idle_add_interp(exec_interval, (gpointer)rb_f_lambda(), 0);
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
    rb_funcall(warn_handler, id_call, 1, rb_str_new2(mesg));
}

static void
gtkmesg(mesg)
    char *mesg;
{
    rb_funcall(mesg_handler, id_call, 1, rb_str_new2(mesg));
}

static void
gtkprint(mesg)
    char *mesg;
{
    rb_funcall(print_handler, id_call, 1, rb_str_new2(mesg));
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
	handler = rb_f_lambda();
    }
    g_set_warning_handler(gtkwarn);
    return handler;
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
	handler = rb_f_lambda();
    }
    g_set_message_handler(gtkmesg);
    return handler;
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
	handler = rb_f_lambda();
    }
    g_set_print_handler(gtkprint);
    return handler;
}

static void
gtkerr(mesg)
    char *mesg;
{
    rb_raise(rb_eRuntimeError, "%s", mesg);
}

void
Init_gtk()
{
    int argc, i;
    char **argv;

    gtk_set_locale();
    gtk_object_list = rb_ary_new();
    rb_global_variable(&gtk_object_list);

    mGtk = rb_define_module("Gtk");

    gObject = rb_define_class_under(mGtk, "Object", rb_cObject);
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
    gEditable = rb_define_class_under(mGtk, "Editable", gWidget);
    gEntry = rb_define_class_under(mGtk, "Entry", gEditable);
    gEventBox = rb_define_class_under(mGtk, "EventBox", gBin);
    gFixed = rb_define_class_under(mGtk, "Fixed", gContainer);
    gGamma = rb_define_class_under(mGtk, "GammaCurve", gVBox);
    gHBBox = rb_define_class_under(mGtk, "HButtonBox", gBBox);
    gVBBox = rb_define_class_under(mGtk, "VButtonBox", gBBox);
    gHBox = rb_define_class_under(mGtk, "HBox", gBox);
    gStatusBar = rb_define_class_under(mGtk, "Statusbar", gHBox);
    gCombo = rb_define_class_under(mGtk, "Combo", gHBox);
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
    gText = rb_define_class_under(mGtk, "Text", gEditable);
    gToolbar = rb_define_class_under(mGtk, "Toolbar", gContainer);
    gTooltips = rb_define_class_under(mGtk, "Tooltips", rb_cData);
    gTree = rb_define_class_under(mGtk, "Tree", gContainer);
    gTreeItem = rb_define_class_under(mGtk, "TreeItem", gItem);
    gViewPort = rb_define_class_under(mGtk, "ViewPort", gBin);

    gAcceleratorTable = rb_define_class_under(mGtk, "AcceleratorTable", rb_cData);
    gStyle = rb_define_class_under(mGtk, "Style", rb_cData);
    gPreviewInfo = rb_define_class_under(mGtk, "PreviewInfo", rb_cData);
    gRequisition = rb_define_class_under(mGtk, "Requisition", rb_cData);
    gAllocation = rb_define_class_under(mGtk, "Allocation", rb_cData);

    mRC = rb_define_module_under(mGtk, "RC");

    mGdk = rb_define_module("Gdk");

    gdkFont = rb_define_class_under(mGdk, "Font", rb_cData);
    gdkColor = rb_define_class_under(mGdk, "Color", rb_cData);
    gdkDrawable = rb_define_class_under(mGdk, "Drawable", rb_cData);
    gdkPixmap = rb_define_class_under(mGdk, "Pixmap", gdkDrawable);
    gdkBitmap = rb_define_class_under(mGdk, "Bitmap", gdkPixmap);
    gdkWindow = rb_define_class_under(mGdk, "Window", gdkDrawable);
    gdkImage = rb_define_class_under(mGdk, "Image", rb_cData);
    gdkVisual = rb_define_class_under(mGdk, "Visual", rb_cData);
    gdkGC = rb_define_class_under(mGdk, "GC", rb_cData);
    gdkGCValues = rb_define_class_under(mGdk, "GCValues", rb_cData);
    gdkRectangle = rb_define_class_under(mGdk, "Rectangle", rb_cData);
    gdkSegment = rb_define_class_under(mGdk, "Segment", rb_cData);
    gdkWindowAttr = rb_define_class_under(mGdk, "WindowAttr", rb_cData);
    gdkCursor = rb_define_class_under(mGdk, "Cursor", rb_cData);
    gdkAtom = rb_define_class_under(mGdk, "Atom", rb_cData);
    gdkColorContext = rb_define_class_under(mGdk, "ColotContext", rb_cData);
    gdkEvent = rb_define_class_under(mGdk, "gdkEvent", rb_cData);

    gdkEventType = rb_define_class_under(mGdk, "gdkEventType", gdkEvent);
    gdkEventAny = rb_define_class_under(mGdk, "gdkEventAny", gdkEvent);
    gdkEventExpose = rb_define_class_under(mGdk, "gdkEventExpose", gdkEvent);
    gdkEventNoExpose = rb_define_class_under(mGdk, "gdkEventNoExpose", gdkEvent);
    gdkEventVisibility = rb_define_class_under(mGdk, "gdkEventVisibility", gdkEvent);
    gdkEventMotion = rb_define_class_under(mGdk, "gdkEventMotion", gdkEvent);
    gdkEventButton = rb_define_class_under(mGdk, "gdkEventButton", gdkEvent);
    gdkEventKey = rb_define_class_under(mGdk, "gdkEventKey", gdkEvent);
    gdkEventCrossing = rb_define_class_under(mGdk, "gdkEventCrossing", gdkEvent);
    gdkEventFocus = rb_define_class_under(mGdk, "gdkEventFocus", gdkEvent);
    gdkEventConfigure = rb_define_class_under(mGdk, "gdkEventConfigure", gdkEvent);
    gdkEventProperty = rb_define_class_under(mGdk, "gdkEventProperty", gdkEvent);
    gdkEventSelection = rb_define_class_under(mGdk, "gdkEventSelection", gdkEvent);
    gdkEventProximity = rb_define_class_under(mGdk, "gdkEventProximity", gdkEvent);
    gdkEventDragBegin = rb_define_class_under(mGdk, "gdkEventDragBegin", gdkEvent);
    gdkEventDragRequest = rb_define_class_under(mGdk, "gdkEventDragRequest", gdkEvent);
    gdkEventDropEnter = rb_define_class_under(mGdk, "gdkEventDropEnter", gdkEvent);
    gdkEventDropLeave = rb_define_class_under(mGdk, "gdkEventDropLeave", gdkEvent);
    gdkEventDropDataAvailable = rb_define_class_under(mGdk, "gdkEventDropDataAvailable", gdkEvent);
    gdkEventClient = rb_define_class_under(mGdk, "gdkEventClient", gdkEvent);
    gdkEventOther = rb_define_class_under(mGdk, "gdkEventOther", gdkEvent);


    /* GtkObject */
    rb_define_method(gObject, "initialize", gobj_initialize, -1);
    rb_define_method(gObject, "set_flags", gobj_set_flags, 1);
    rb_define_method(gObject, "unset_flags", gobj_unset_flags, 1);
    rb_define_method(gObject, "destroy", gobj_destroy, 0);
    rb_define_method(gObject, "signal_connect", gobj_sig_connect, -1);
    rb_define_method(gObject, "signal_connect_after", gobj_sig_connect_after, -1);
    rb_define_method(gObject, "singleton_method_added", gobj_smethod_added, 1);
    rb_define_method(gObject, "==", grb_obj_equal, 1);
    rb_define_method(gObject, "inspect", gobj_inspect, 0);

    /* Widget */
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
    rb_define_method(gWidget, "draw", widget_draw, -1);
    rb_define_method(gWidget, "draw_focus", widget_draw_focus, 0);
    rb_define_method(gWidget, "draw_default", widget_draw_default, 0);
    rb_define_method(gWidget, "draw_children", widget_draw_children, 0);
    rb_define_method(gWidget, "size_request", widget_size_request, 1);
    rb_define_method(gWidget, "size_allocate", widget_size_allocate, 1);
    rb_define_method(gWidget, "install_accelerator", widget_inst_accel, 4);
    rb_define_method(gWidget, "remove_accelerator", widget_rm_accel, 4);
    rb_define_method(gWidget, "event", widget_event, 1);
    rb_define_method(gWidget, "activate", widget_activate, 0);
    rb_define_method(gWidget, "grab_focus", widget_grab_focus, 0);
    rb_define_method(gWidget, "grab_default", widget_grab_default, 0);
    rb_define_method(gWidget, "set_state", widget_set_state, 1);
    rb_define_method(gWidget, "visible?", widget_visible, 0);
    rb_define_method(gWidget, "mapped?", widget_mapped, 0);
    rb_define_method(gWidget, "reparent", widget_reparent, 1);
    rb_define_method(gWidget, "popup", widget_popup, 2);
    rb_define_method(gWidget, "intersect", widget_intersect, 2);
    rb_define_method(gWidget, "basic", widget_basic, 0);
    rb_define_method(gWidget, "get_name", widget_get_name, 0);
    rb_define_method(gWidget, "set_name", widget_set_name, 1);
    rb_define_method(gWidget, "set_parent", widget_set_parent, 1);
    rb_define_method(gWidget, "set_sensitive", widget_set_sensitive, 1);
    rb_define_method(gWidget, "set_usize", widget_set_usize, 2);
    rb_define_method(gWidget, "set_uposition", widget_set_uposition, 2);
    rb_define_method(gWidget, "set_style", widget_set_style, 1);
    rb_define_method(gWidget, "set_events", widget_set_events, 1);
    rb_define_method(gWidget, "set_extension_events", widget_set_eevents, 1);
    rb_define_method(gWidget, "unparent", widget_unparent, 0);
    rb_define_method(gWidget, "allocation", widget_get_alloc, 0);
    rb_define_method(gWidget, "requisition", widget_get_requisition, 0);
    rb_define_method(gWidget, "set_requisition", widget_set_requisition, 2);
    rb_define_method(gWidget, "state", widget_state, 0);
    rb_define_method(gWidget, "get_toplevel", widget_get_toplevel, 0);
    rb_define_method(gWidget, "get_ancestor", widget_get_ancestor, 1);
    rb_define_method(gWidget, "get_colormap", widget_get_colormap, 0);
    rb_define_method(gWidget, "get_visual", widget_get_visual, 0);
    rb_define_method(gWidget, "get_style", widget_get_style, 0);
    rb_define_method(gWidget, "style", widget_get_style, 0);
    rb_define_method(gWidget, "get_events", widget_get_events, 0);
    rb_define_method(gWidget, "get_extension_events", widget_get_eevents, 0);
    rb_define_method(gWidget, "get_pointer", widget_get_pointer, 0);
    rb_define_method(gWidget, "ancestor?", widget_is_ancestor, 1);
    rb_define_method(gWidget, "child?", widget_is_child, 1);
    rb_define_method(gWidget, "window", widget_window, 0);
    rb_define_method(gWidget, "shape_combine_mask", widget_shape_combine_mask, 3);

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
    rb_define_method(gMisc, "xalign", misc_get_xalign, 0);
    rb_define_method(gMisc, "yalign", misc_get_yalign, 0);
    rb_define_method(gMisc, "xpad", misc_get_xpad, 0);
    rb_define_method(gMisc, "ypad", misc_get_ypad, 0);
    
    /* Arrow */
    rb_define_method(gArrow, "initialize", arrow_initialize, 2);
    rb_define_method(gArrow, "set", arrow_set, 2);

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
    rb_define_method(gTButton, "active", tbtn_active, 0);

    /* CheckButton */
    rb_define_method(gCButton, "initialize", cbtn_initialize, -1);

    /* RadioButton */
    rb_define_method(gRButton, "initialize", rbtn_initialize, -1);
    rb_define_method(gRButton, "group", rbtn_group, 0);

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
    rb_define_method(gCList, "initialize", clist_initialize, 1);
    rb_define_method(gCList, "set_border", clist_set_border, 1);
    rb_define_method(gCList, "set_selection_mode", clist_set_sel_mode, 1);
    rb_define_method(gCList, "set_policy", clist_set_policy, 2);
    rb_define_method(gCList, "freeze", clist_freeze, 0);
    rb_define_method(gCList, "thaw", clist_thaw, 0);
    rb_define_method(gCList, "column_titles_show", clist_col_titles_show, 0);
    rb_define_method(gCList, "column_titles_hide", clist_col_titles_hide, 0);
    rb_define_method(gCList, "column_title_active", clist_col_title_active, 1);
    rb_define_method(gCList, "column_title_passive", clist_col_title_passive, 1);
    rb_define_method(gCList, "column_titles_active", clist_col_titles_active, 0);
    rb_define_method(gCList, "column_titles_passive", clist_col_titles_passive, 0);
    rb_define_method(gCList, "set_column_title", clist_set_col_title, 2);
    rb_define_method(gCList, "set_column_widget", clist_set_col_wigdet, 2);
    rb_define_method(gCList, "set_column_justification", clist_set_col_just, 2);
    rb_define_method(gCList, "set_column_width", clist_set_col_width, 2);
    rb_define_method(gCList, "set_row_height", clist_set_row_height, 1);
    rb_define_method(gCList, "moveto", clist_moveto, 4);
    rb_define_method(gCList, "set_text", clist_set_text, 3);
    rb_define_method(gCList, "set_pixmap", clist_set_pixmap, 4);
    rb_define_method(gCList, "set_pixtext", clist_set_pixtext, 6);
    rb_define_method(gCList, "set_foreground", clist_set_foreground, 2);
    rb_define_method(gCList, "set_background", clist_set_background, 2);
    rb_define_method(gCList, "set_shift", clist_set_shift, 4);
    rb_define_method(gCList, "append", clist_append, 1);
    rb_define_method(gCList, "insert", clist_insert, 2);
    rb_define_method(gCList, "remove", clist_remove, 1);
    rb_define_method(gCList, "set_row_data", clist_set_row_data, 2);
    rb_define_method(gCList, "get_row_data", clist_get_row_data, 1);
    rb_define_method(gCList, "select_row", clist_select_row, 2);
    rb_define_method(gCList, "unselect_row", clist_unselect_row, 2);
    rb_define_method(gCList, "clear", clist_clear, 0);

    /* Window */
    rb_define_method(gWindow, "initialize", gwin_initialize, 1);
    rb_define_method(gWindow, "set_title", gwin_set_title, 1);
    rb_define_method(gWindow, "set_policy", gwin_set_policy, 3);
    rb_define_method(gWindow, "set_wmclass", gwin_set_wmclass, 1);
    rb_define_method(gWindow, "set_focus", gwin_set_focus, 1);
    rb_define_method(gWindow, "set_default", gwin_set_default, 1);
    rb_define_method(gWindow, "add_accelerator_table", gwin_add_accel, 1);
    rb_define_method(gWindow, "remove_accelerator_table", gwin_rm_accel, 1);
    rb_define_method(gWindow, "position", gwin_position, 1);
    rb_define_method(gWindow, "grab_add", gwin_grab_add, 0);
    rb_define_method(gWindow, "grab_remove", gwin_grab_remove, 0);
    rb_define_method(gWindow, "shape_combine_mask", gwin_shape_combine_mask, 3);

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

    /* Editable */
    rb_define_method(gEditable, "select_region", edit_sel_region, 2);
    rb_define_method(gEditable, "insert_text", edit_insert_text, 3);
    rb_define_method(gEditable, "delete_text", edit_delete_text, 2);
    rb_define_method(gEditable, "get_chars", edit_get_chars, 2);
    rb_define_method(gEditable, "cut_clipboard", edit_cut_clipboard, 1);
    rb_define_method(gEditable, "copy_clipboard", edit_copy_clipboard, 1);
    rb_define_method(gEditable, "paste_clipboard", edit_paste_clipboard, 1);
    rb_define_method(gEditable, "claim_selection", edit_claim_selection, 2);
    rb_define_method(gEditable, "delete_selection", edit_delete_selection, 0);
    rb_define_method(gEditable, "changed", edit_changed, 0);

    /* Entry */
    rb_define_method(gEntry, "initialize", entry_initialize, 0);
    rb_define_method(gEntry, "set_text", entry_set_text, 1);
    rb_define_method(gEntry, "append_text", entry_append_text, 1);
    rb_define_method(gEntry, "prepend_text", entry_prepend_text, 1);
    rb_define_method(gEntry, "set_position", entry_set_position, 1);
    rb_define_method(gEntry, "get_text", entry_get_text, 0);
    rb_define_method(gEntry, "set_visibility", entry_set_visibility, 1);
    rb_define_method(gEntry, "set_editable", entry_set_editable, 1);
    rb_define_method(gEntry, "set_max_length", entry_set_max_length, 1);

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
			       hbbox_get_layout_default, 0);
    rb_define_singleton_method(gHBBox, "set_spacing_default",
			       hbbox_set_spacing_default, 1);
    rb_define_singleton_method(gHBBox, "set_layout_default",
			       hbbox_set_layout_default, 1);

    /* VButtonBox */
    rb_define_method(gVBBox, "initialize", vbbox_initialize, 0);
    rb_define_singleton_method(gVBBox, "get_spacing_default",
			       vbbox_get_spacing_default, 0);
    rb_define_singleton_method(gVBBox, "get_layout_default",
			       vbbox_get_layout_default, 0);
    rb_define_singleton_method(gVBBox, "set_spacing_default",
			       vbbox_set_spacing_default, 1);
    rb_define_singleton_method(gVBBox, "set_layout_default",
			       vbbox_set_layout_default, 1);

    /* HBox */
    rb_define_method(gHBox, "initialize", hbox_initialize, -1);

    /* Statusbar */
    rb_define_method(gStatusBar, "initialize", statusbar_initialize, 0);
    rb_define_method(gStatusBar, "push", statusbar_push, 2);
    rb_define_method(gStatusBar, "pop", statusbar_pop, 1);
    rb_define_method(gStatusBar, "get_context_id", statusbar_get_context_id, 1);
    rb_define_method(gStatusBar, "remove", statusbar_remove, 2);

    /* Combo */
    rb_define_method(gCombo, "initialize", combo_initialize, 0);
    rb_define_method(gCombo, "set_value_in_list", combo_val_in_list, 2);
    rb_define_method(gCombo, "set_use_arrows", combo_use_arrows, 1);
    rb_define_method(gCombo, "set_case_sensitive", combo_case_sensitive, 1);
    rb_define_method(gCombo, "set_item_string", combo_item_string, 2);
    rb_define_method(gCombo, "set_popdown_strings", combo_popdown_strings, 1);
    rb_define_method(gCombo, "disable_activate", combo_disable_activate, 0);

    rb_define_method(gCombo, "entry", combo_entry, 0);
    rb_define_method(gCombo, "button", combo_button, 0);
    rb_define_method(gCombo, "popup", combo_popup, 0);
    rb_define_method(gCombo, "popwin", combo_popwin, 0);
    rb_define_method(gCombo, "list", combo_list, 0);

    /* Paned */
    rb_define_method(gPaned, "add1", paned_add1, 1);
    rb_define_method(gPaned, "add2", paned_add2, 1);
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
    rb_define_method(gLabel, "get", label_get, 0);
    rb_define_method(gLabel, "set", label_set, 1);
    rb_define_method(gLabel, "jtype", label_get_jtype, 0);
    rb_define_method(gLabel, "jtype=", label_set_jtype, 1);

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
    rb_define_method(gMenu, "popdown", menu_popdown, 0);
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
    rb_define_method(gOptionMenu, "remove_menu", omenu_remove_menu, 0);
    rb_define_method(gOptionMenu, "set_history", omenu_set_history, 1);

    /* Pixmap */
    rb_define_method(gPixmap, "initialize", pixmap_initialize, 2);
    rb_define_method(gPixmap, "set", pixmap_set, 2);
    rb_define_method(gPixmap, "get", pixmap_get, 0);

    /* Preview */
    rb_define_method(gPreview, "initialize", preview_initialize, 1);
    rb_define_method(gPreview, "size", preview_size, 2);
    rb_define_method(gPreview, "put", preview_put, 8);
    rb_define_method(gPreview, "put_row", preview_put_row, 5);
    rb_define_method(gPreview, "draw_row", preview_draw_row, 4);
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
    rb_define_method(gToolbar, "append_item", tbar_append_item, 5);
    rb_define_method(gToolbar, "prepend_item", tbar_prepend_item, 5);
    rb_define_method(gToolbar, "insert_item", tbar_insert_item, 6);
    rb_define_method(gToolbar, "append_space", tbar_append_space, 0);
    rb_define_method(gToolbar, "prepend_space", tbar_prepend_space, 0);
    rb_define_method(gToolbar, "insert_space", tbar_insert_space, 1);
    rb_define_method(gToolbar, "set_orientation", tbar_set_orientation, 1);
    rb_define_method(gToolbar, "set_style", tbar_set_style, 1);
    rb_define_method(gToolbar, "set_space_size", tbar_set_space_size, 1);
    rb_define_method(gToolbar, "set_tooltips", tbar_set_tooltips, 1);

    /* Tooltips */
    rb_define_method(gTooltips, "initialize", ttips_initialize, 0);
    rb_define_method(gTooltips, "set_tip", ttips_set_tip, 3);
    rb_define_method(gTooltips, "set_delay", ttips_set_delay, 1);
    rb_define_method(gTooltips, "set_colors", ttips_set_colors, 2);
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
    rb_define_singleton_method(gStyle, "new", style_s_new, 0);
    rb_define_method(gStyle, "copy", style_copy, 0);
    rb_define_method(gStyle, "clone", style_copy, 0);
    rb_define_method(gStyle, "dup", style_copy, 0);
    rb_define_method(gStyle, "attach", style_attach, 1);
    rb_define_method(gStyle, "detach", style_detach, 0);
    rb_define_method(gStyle, "set_background", style_set_background, 1);
    rb_define_method(gStyle, "fg", style_fg, 1);
    rb_define_method(gStyle, "bg", style_bg, 1);
    rb_define_method(gStyle, "light", style_light, 1);
    rb_define_method(gStyle, "dark", style_dark, 1);
    rb_define_method(gStyle, "mid", style_mid, 1);
    rb_define_method(gStyle, "text", style_text, 1);
    rb_define_method(gStyle, "base", style_base, 1);
    rb_define_method(gStyle, "set_fg", style_set_fg, 4);
    rb_define_method(gStyle, "set_bg", style_set_bg, 4);
    rb_define_method(gStyle, "set_light", style_set_light, 4);
    rb_define_method(gStyle, "set_dark", style_set_dark, 4);
    rb_define_method(gStyle, "set_mid", style_set_mid, 4);
    rb_define_method(gStyle, "set_text", style_set_text, 4);
    rb_define_method(gStyle, "set_base", style_set_base, 4);

    rb_define_method(gStyle, "black", style_black, 0);
    rb_define_method(gStyle, "white", style_white, 0);
    rb_define_method(gStyle, "font", style_font, 0);
    rb_define_method(gStyle, "set_font", style_set_font, 1);
    rb_define_method(gStyle, "fg_gc", style_fg_gc, 1);
    rb_define_method(gStyle, "bg_gc", style_bg_gc, 1);
    rb_define_method(gStyle, "light_gc", style_light_gc, 1);
    rb_define_method(gStyle, "dark_gc", style_dark_gc, 1);
    rb_define_method(gStyle, "mid_gc", style_mid_gc, 1);
    rb_define_method(gStyle, "text_gc", style_text_gc, 1);
    rb_define_method(gStyle, "base_gc", style_base_gc, 1);
    rb_define_method(gStyle, "black_gc", style_black_gc, 0);
    rb_define_method(gStyle, "white_gc", style_white_gc, 0);
    rb_define_method(gStyle, "bg_pixmap", style_bg_pixmap, 1);
#if 0
    rb_define_method(gStyle, "draw_hline", style_draw_hline, 5);
    rb_define_method(gStyle, "draw_vline", style_draw_vline, 5);
    rb_define_method(gStyle, "draw_shadow", style_draw_shadow, 7);
    rb_define_method(gStyle, "draw_polygon", style_draw_polygon, 6);
    rb_define_method(gStyle, "draw_arrow", style_draw_arrow, 9);
    rb_define_method(gStyle, "draw_diamond", style_draw_diamond, 7);
    rb_define_method(gStyle, "draw_oval", style_draw_oval, 7);
    rb_define_method(gStyle, "draw_string", style_draw_string, 5);
#endif

    rb_define_method(gAllocation, "x", gallocation_x, 0);
    rb_define_method(gAllocation, "y", gallocation_y, 0);
    rb_define_method(gAllocation, "width", gallocation_w, 0);
    rb_define_method(gAllocation, "height", gallocation_h, 0);

    rb_define_method(gRequisition, "width", grequisition_w, 0);
    rb_define_method(gRequisition, "height", grequisition_h, 0);
	/*
    rb_define_method(gRequisition, "width=", grequisition_set_w, 1);
    rb_define_method(gRequisition, "height=", grequisition_set_h, 1);
	*/

    /* Gtk module */
    rb_define_module_function(mGtk, "main", gtk_m_main, 0);
    rb_define_module_function(mGtk, "timeout_add", timeout_add, 1);
    rb_define_module_function(mGtk, "timeout_remove", timeout_remove, 1);
    rb_define_module_function(mGtk, "idle_add", idle_add, 0);
    rb_define_module_function(mGtk, "idle_remove", idle_remove, 1);

    rb_define_module_function(mGtk, "set_warning_handler",
			      set_warning_handler, -1);
    rb_define_module_function(mGtk, "set_message_handler",
			      set_message_handler, -1);
    rb_define_module_function(mGtk, "set_print_handler",
			      set_print_handler, -1);

    /* RC module */
    rb_define_module_function(mRC, "parse", gtk_rc_m_parse, 1);
    rb_define_module_function(mRC, "parse_string", gtk_rc_m_parse_string, 1);
    rb_define_module_function(mRC, "get_style", gtk_rc_m_get_style, 1);
    rb_define_module_function(mRC, "add_widget_name_style",
			      gtk_rc_m_add_widget_name_style, 1);
    rb_define_module_function(mRC, "add_widget_class_style",
			      gtk_rc_m_add_widget_class_style, 1);

    /* Gdk module */
    /* GdkFont */
    rb_define_singleton_method(gdkFont, "load_font", gdkfnt_load_font, 1);
    rb_define_singleton_method(gdkFont, "new", gdkfnt_new, 1);
    rb_define_singleton_method(gdkFont, "load_fontset", gdkfnt_load_fontset, 1);
    rb_define_method(gdkFont, "string_width", gdkfnt_string_width, 1);
    rb_define_method(gdkFont, "ascent", gdkfnt_ascent, 0);
    rb_define_method(gdkFont, "descent", gdkfnt_descent, 0);
    rb_define_method(gdkFont, "==", gdkfnt_equal, 1);

    /* GdkDrawable */
    rb_define_method(gdkDrawable, "draw_point", gdkdraw_draw_point, 3);
    rb_define_method(gdkDrawable, "draw_line", gdkdraw_draw_line, 5);
    rb_define_method(gdkDrawable, "draw_rectangle", gdkdraw_draw_rect, 6);
    rb_define_method(gdkDrawable, "draw_arc", gdkdraw_draw_arc, 8);
    rb_define_method(gdkDrawable, "draw_polygon", gdkdraw_draw_poly, 3);
    rb_define_method(gdkDrawable, "draw_string", gdkdraw_draw_text, 5);
    rb_define_method(gdkDrawable, "draw_text", gdkdraw_draw_text, 5);
    rb_define_method(gdkDrawable, "draw_pixmap", gdkdraw_draw_pmap, 8);
    rb_define_method(gdkDrawable, "draw_bitmap", gdkdraw_draw_bmap, 8);
    rb_define_method(gdkDrawable, "draw_image", gdkdraw_draw_image, 8);
    rb_define_method(gdkDrawable, "draw_points", gdkdraw_draw_pnts, 2);
    rb_define_method(gdkDrawable, "draw_segments", gdkdraw_draw_segs, 2);
    rb_define_method(gdkDrawable, "get_geometry", gdkdraw_get_geometry, 0);

    /* GdkPixmap */
    rb_define_singleton_method(gdkPixmap, "new", gdkpmap_s_new, 4);
    rb_define_singleton_method(gdkPixmap, "create_from_data",
			       gdkpmap_create_from_data, 7);
    rb_define_singleton_method(gdkPixmap, "create_from_xpm",
			       gdkpmap_create_from_xpm, 3);
    rb_define_singleton_method(gdkPixmap, "create_from_xpm_d",
			       gdkpmap_create_from_xpm_d, 3);

    /* GdkBitmap */
    rb_define_singleton_method(gdkBitmap, "new", gdkbmap_s_new, 3);
    rb_define_singleton_method(gdkBitmap, "create_from_data",
			       gdkbmap_create_from_data, 4);

    /* GdkWindow */
    rb_define_method(gdkWindow, "get_pointer", gdkwin_get_pointer, 0);
    rb_define_method(gdkWindow, "pointer_grab", gdkwin_pointer_grab, 5);
    rb_define_method(gdkWindow, "pointer_ungrab", gdkwin_pointer_ungrab, 1);
    rb_define_singleton_method(gdkWindow, "foreign_new", gdkwin_foreign_new, 1);
    rb_define_singleton_method(gdkWindow, "root_window", gdkwin_root_window, 0);
    rb_define_method(gdkWindow, "clear", gdkwin_clear, 0);
    rb_define_method(gdkWindow, "clear_area", gdkwin_clear_area, 4);
    rb_define_method(gdkWindow, "clear_area_e", gdkwin_clear, 4);
    rb_define_method(gdkWindow, "set_background", gdkwin_set_background, 1);
    rb_define_method(gdkWindow, "set_back_pixmap", gdkwin_set_back_pixmap, 2);

    /* GdkGC */
    rb_define_singleton_method(gdkGC, "new", gdkgc_s_new, 1);
    rb_define_method(gdkGC, "copy", gdkgc_copy, 1);
    rb_define_method(gdkGC, "destroy", gdkgc_destroy, 0);
    rb_define_method(gdkGC, "set_function", gdkgc_set_function, 1);
    rb_define_method(gdkGC, "set_foreground", gdkgc_set_foreground, 1);
    rb_define_method(gdkGC, "set_background", gdkgc_set_background, 1);
    rb_define_method(gdkGC, "set_clip_mask", gdkgc_set_clip_mask, 1);
    rb_define_method(gdkGC, "set_clip_origin", gdkgc_set_clip_origin, 2);
    rb_define_method(gdkGC, "set_clip_rectangle", gdkgc_set_clip_rectangle, 1);
	/* rb_define_method(gdkGC, "set_clip_region", gdkgc_set_clip_region, 1); */

    /* GdkImage */
    rb_define_singleton_method(gdkImage, "new_bitmap", gdkimage_s_newbmap, 4);
    rb_define_singleton_method(gdkImage, "new", gdkimage_s_new, 4);
    rb_define_singleton_method(gdkImage, "get", gdkimage_s_get, 5);
    rb_define_method(gdkImage, "put_pixel", gdkimage_put_pixel, 3);
    rb_define_method(gdkImage, "get_pixel", gdkimage_get_pixel, 2);
    rb_define_method(gdkImage, "destroy", gdkimage_destroy, 0);

    /* GdkRectangle */
    rb_define_singleton_method(gdkRectangle, "new", gdkrect_s_new, 4);
    rb_define_method(gdkRectangle, "x", gdkrect_x, 0);
    rb_define_method(gdkRectangle, "y", gdkrect_y, 0);
    rb_define_method(gdkRectangle, "width", gdkrect_w, 0);
    rb_define_method(gdkRectangle, "height", gdkrect_h, 0);

    /* GdkEvent */
    rb_define_method(gdkEvent, "type", gdkevent_type, 0);

    /* GdkEventExpose */
    rb_define_method(gdkEventExpose, "area", gdkeventexpose_area, 0);

    /* GdkEventButton */
    rb_define_method(gdkEventButton, "x", gdkeventbutton_x, 0);
    rb_define_method(gdkEventButton, "y", gdkeventbutton_y, 0);
    rb_define_method(gdkEventButton, "button", gdkeventbutton_button, 0);

    /* GdkEventMotion */
    rb_define_method(gdkEventMotion, "window", gdkeventmotion_window, 0);
    rb_define_method(gdkEventMotion, "x", gdkeventmotion_x, 0);
    rb_define_method(gdkEventMotion, "y", gdkeventmotion_y, 0);
    rb_define_method(gdkEventMotion, "state", gdkeventmotion_state, 0);
    rb_define_method(gdkEventMotion, "is_hint", gdkeventmotion_is_hint, 0);

    /* constants */
    rb_define_const(mGtk, "VISIBLE", INT2FIX(GTK_VISIBLE));
    rb_define_const(mGtk, "MAPPED", INT2FIX(GTK_MAPPED));
    rb_define_const(mGtk, "REALIZED", INT2FIX(GTK_REALIZED));
    rb_define_const(mGtk, "SENSITIVE", INT2FIX(GTK_SENSITIVE));
    rb_define_const(mGtk, "PARENT_SENSITIVE", INT2FIX(GTK_PARENT_SENSITIVE));
    rb_define_const(mGtk, "NO_WINDOW", INT2FIX(GTK_NO_WINDOW));
    rb_define_const(mGtk, "HAS_FOCUS", INT2FIX(GTK_HAS_FOCUS));
    rb_define_const(mGtk, "CAN_FOCUS", INT2FIX(GTK_CAN_FOCUS));
    rb_define_const(mGtk, "HAS_DEFAULT", INT2FIX(GTK_HAS_DEFAULT));
    rb_define_const(mGtk, "CAN_DEFAULT", INT2FIX(GTK_CAN_DEFAULT));
    rb_define_const(mGtk, "BASIC", INT2FIX(GTK_BASIC));

    /* GtkWindowType */
    rb_define_const(mGtk, "WINDOW_TOPLEVEL", INT2FIX(GTK_WINDOW_TOPLEVEL));
    rb_define_const(mGtk, "WINDOW_DIALOG", INT2FIX(GTK_WINDOW_DIALOG));
    rb_define_const(mGtk, "WINDOW_POPUP", INT2FIX(GTK_WINDOW_POPUP));

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

    /* GtkJustification */
    rb_define_const(mGtk, "JUSTIFY_LEFT", INT2FIX(GTK_JUSTIFY_LEFT));
    rb_define_const(mGtk, "JUSTIFY_RIGHT", INT2FIX(GTK_JUSTIFY_RIGHT));
    rb_define_const(mGtk, "JUSTIFY_CENTER", INT2FIX(GTK_JUSTIFY_CENTER));
    rb_define_const(mGtk, "JUSTIFY_FILL", INT2FIX(GTK_JUSTIFY_FILL));

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

    /* GdkMiscMode */
    rb_define_const(mGdk, "FUNCTION_COPY", INT2FIX(GDK_COPY));
    rb_define_const(mGdk, "FUNCTION_INVERT", INT2FIX(GDK_INVERT));
    rb_define_const(mGdk, "FUNCTION_XOR", INT2FIX(GDK_XOR));

    /* GdkExtensionMode */
    rb_define_const(mGdk, "EXTENSION_EVENTS_NONE", INT2FIX(GDK_EXTENSION_EVENTS_NONE));
    rb_define_const(mGdk, "EXTENSION_EVENTS_ALL", INT2FIX(GDK_EXTENSION_EVENTS_ALL));
    rb_define_const(mGdk, "EXTENSION_EVENTS_CURSOR", INT2FIX(GDK_EXTENSION_EVENTS_CURSOR));

    rb_define_const(mGdk, "IMAGE_NORMAL", INT2FIX(GDK_IMAGE_NORMAL));
    rb_define_const(mGdk, "IMAGE_SHARED", INT2FIX(GDK_IMAGE_SHARED));
    rb_define_const(mGdk, "IMAGE_FASTEST", INT2FIX(GDK_IMAGE_FASTEST));

    rb_define_const(mGdk, "CURRENT_TIME", INT2FIX(GDK_CURRENT_TIME));
    rb_define_const(mGdk, "NONE", INT2FIX(GDK_NONE));
    rb_define_const(mGdk, "PARENT_RELATIVE", INT2FIX(GDK_PARENT_RELATIVE));

    /* GdkEventMask */
    rb_define_const(mGdk, "EXPOSURE_MASK", INT2FIX(GDK_EXPOSURE_MASK));
    rb_define_const(mGdk, "POINTER_MOTION_MASK", INT2FIX(GDK_POINTER_MOTION_MASK));
    rb_define_const(mGdk, "POINTER_MOTION_HINT_MASK", INT2FIX(GDK_POINTER_MOTION_HINT_MASK));
    rb_define_const(mGdk, "BUTTON_MOTION_MASK", INT2FIX(GDK_BUTTON_MOTION_MASK));
    rb_define_const(mGdk, "BUTTON1_MOTION_MASK", INT2FIX(GDK_BUTTON1_MOTION_MASK));
    rb_define_const(mGdk, "BUTTON2_MOTION_MASK", INT2FIX(GDK_BUTTON2_MOTION_MASK));
    rb_define_const(mGdk, "BUTTON3_MOTION_MASK", INT2FIX(GDK_BUTTON3_MOTION_MASK));
    rb_define_const(mGdk, "BUTTON_PRESS_MASK", INT2FIX(GDK_BUTTON_PRESS_MASK));
    rb_define_const(mGdk, "BUTTON_RELEASE_MASK", INT2FIX(GDK_BUTTON_RELEASE_MASK));
    rb_define_const(mGdk, "KEY_PRESS_MASK", INT2FIX(GDK_KEY_PRESS_MASK));
    rb_define_const(mGdk, "KEY_RELEASE_MASK", INT2FIX(GDK_KEY_RELEASE_MASK));
    rb_define_const(mGdk, "ENTER_NOTIFY_MASK", INT2FIX(GDK_ENTER_NOTIFY_MASK));
    rb_define_const(mGdk, "LEAVE_NOTIFY_MASK", INT2FIX(GDK_LEAVE_NOTIFY_MASK));
    rb_define_const(mGdk, "FOCUS_CHANGE_MASK", INT2FIX(GDK_FOCUS_CHANGE_MASK));
    rb_define_const(mGdk, "STRUCTURE_MASK", INT2FIX(GDK_STRUCTURE_MASK));
    rb_define_const(mGdk, "PROPERTY_CHANGE_MASK", INT2FIX(GDK_PROPERTY_CHANGE_MASK));
    rb_define_const(mGdk, "VISIBILITY_NOTIFY_MASK", INT2FIX(GDK_VISIBILITY_NOTIFY_MASK));
    rb_define_const(mGdk, "PROXIMITY_IN_MASK", INT2FIX(GDK_PROXIMITY_IN_MASK));
    rb_define_const(mGdk, "PROXIMITY_OUT_MASK", INT2FIX(GDK_PROXIMITY_OUT_MASK));
    rb_define_const(mGdk, "ALL_EVENTS_MASK", INT2FIX(GDK_ALL_EVENTS_MASK));


    /* GdkModifierType */
    rb_define_const(mGdk, "SHIFT_MASK", INT2FIX(GDK_SHIFT_MASK));
    rb_define_const(mGdk, "LOCK_MASK", INT2FIX(GDK_LOCK_MASK));
    rb_define_const(mGdk, "CONTROL_MASK", INT2FIX(GDK_CONTROL_MASK));
    rb_define_const(mGdk, "MOD1_MASK", INT2FIX(GDK_MOD1_MASK));
    rb_define_const(mGdk, "MOD2_MASK", INT2FIX(GDK_MOD2_MASK));
    rb_define_const(mGdk, "MOD3_MASK", INT2FIX(GDK_MOD3_MASK));
    rb_define_const(mGdk, "MOD4_MASK", INT2FIX(GDK_MOD4_MASK));
    rb_define_const(mGdk, "MOD5_MASK", INT2FIX(GDK_MOD5_MASK));
    rb_define_const(mGdk, "BUTTON1_MASK", INT2FIX(GDK_BUTTON1_MASK));
    rb_define_const(mGdk, "BUTTON2_MASK", INT2FIX(GDK_BUTTON2_MASK));
    rb_define_const(mGdk, "BUTTON3_MASK", INT2FIX(GDK_BUTTON3_MASK));
    rb_define_const(mGdk, "BUTTON4_MASK", INT2FIX(GDK_BUTTON4_MASK));
    rb_define_const(mGdk, "BUTTON5_MASK", INT2FIX(GDK_BUTTON5_MASK));


    argc = RARRAY(rb_argv)->len;
    argv = ALLOCA_N(char*,argc+1);
    argv[0] = STR2CSTR(rb_argv0);
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

	gtk_init(&argc, &argv);

	signal(SIGHUP,  sigfunc[0]);
	signal(SIGINT,  sigfunc[1]);
	signal(SIGQUIT, sigfunc[2]);
	signal(SIGBUS,  sigfunc[3]);
	signal(SIGSEGV, sigfunc[4]);
	signal(SIGPIPE, sigfunc[5]);
	signal(SIGTERM, sigfunc[6]);
    }

    for (i=1;i<argc;i++) {
	RARRAY(rb_argv)->ptr[i-1] = rb_str_taint(rb_str_new2(argv[i]));
    }
    RARRAY(rb_argv)->len = argc-1;

    id_call = rb_intern("call");
    id_gtkdata = rb_intern("gtkdata");
    id_relatives = rb_intern("relatives");
#if 0
    gtk_idle_add((GtkFunction)idle, 0);
#else
    /* use timeout to avoid busy wait */
    gtk_timeout_add(1, (GtkFunction)idle, 0);
#endif

    g_set_error_handler(gtkerr);
    g_set_warning_handler(gtkerr);
    rb_global_variable(&warn_handler);
    rb_global_variable(&mesg_handler);
    rb_global_variable(&print_handler);
}
