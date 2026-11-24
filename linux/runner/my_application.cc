#include "my_application.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

static gint saved_width = 1440;
static gint saved_height = 900;
static gint saved_x = -1;
static gint saved_y = -1;
static gboolean saved_maximized = FALSE;
static guint _save_pending = 0;

static const gchar* kWindowStateFilename = "window_state.json";

static gchar* get_config_dir() {
  const gchar* xdg = g_getenv("XDG_CONFIG_HOME");
  if (xdg != nullptr && xdg[0] != '\0') {
    return g_strdup(xdg);
  }
  const gchar* home = g_getenv("HOME");
  if (home != nullptr && home[0] != '\0') {
    return g_build_path("/", home, ".config", nullptr);
  }
  return g_strdup(".config");
}

static gchar* get_window_state_path() {
  gchar* config_dir = get_config_dir();
  gchar* app_dir = g_build_filename(config_dir, "yesplaymusic", nullptr);
  g_free(config_dir);
  gchar* path = g_build_filename(app_dir, kWindowStateFilename, nullptr);
  g_free(app_dir);
  return path;
}

static gboolean read_json_int(const gchar* json, const gchar* key, gint* out) {
  gchar pattern[64];
  snprintf(pattern, sizeof(pattern), "\"%s\":", key);
  const gchar* found = strstr(json, pattern);
  if (found == nullptr) {
    return FALSE;
  }
  found += strlen(pattern);
  while (*found == ' ' || *found == '\t' || *found == '\n' || *found == '\r') {
    found++;
  }
  gchar* end = nullptr;
  long value = strtol(found, &end, 10);
  if (end == found) {
    return FALSE;
  }
  *out = static_cast<gint>(value);
  return TRUE;
}

static gboolean read_json_bool(const gchar* json, const gchar* key,
                               gboolean* out) {
  gchar pattern[64];
  snprintf(pattern, sizeof(pattern), "\"%s\":", key);
  const gchar* found = strstr(json, pattern);
  if (found == nullptr) {
    return FALSE;
  }
  found += strlen(pattern);
  while (*found == ' ' || *found == '\t' || *found == '\n' || *found == '\r') {
    found++;
  }
  if (strncmp(found, "true", 4) == 0) {
    *out = TRUE;
    return TRUE;
  }
  if (strncmp(found, "false", 5) == 0) {
    *out = FALSE;
    return TRUE;
  }
  return FALSE;
}

static void load_window_state() {
  gchar* path = get_window_state_path();
  FILE* file = fopen(path, "r");
  g_free(path);
  if (file == nullptr) {
    return;
  }
  fseek(file, 0, SEEK_END);
  long length = ftell(file);
  fseek(file, 0, SEEK_SET);
  if (length <= 0) {
    fclose(file);
    return;
  }
  gchar* json = static_cast<gchar*>(g_malloc(length + 1));
  size_t read = fread(json, 1, length, file);
  json[read] = '\0';
  fclose(file);

  gint width = 0;
  gint height = 0;
  gint x = 0;
  gint y = 0;
  gboolean maximized = FALSE;

  if (read_json_int(json, "width", &width) && width > 0) {
    saved_width = width;
  }
  if (read_json_int(json, "height", &height) && height > 0) {
    saved_height = height;
  }
  if (read_json_int(json, "x", &x)) {
    saved_x = x;
  }
  if (read_json_int(json, "y", &y)) {
    saved_y = y;
  }
  read_json_bool(json, "is_maximized", &maximized);
  saved_maximized = maximized;

  g_free(json);
}

static void save_window_state(GtkWindow* window) {
  gboolean maximized = gtk_window_is_maximized(window);

  gchar* path = get_window_state_path();
  gchar* config_dir = get_config_dir();
  gchar* app_dir = g_build_filename(config_dir, "yesplaymusic", nullptr);
  g_free(config_dir);
  g_mkdir_with_parents(app_dir, 0755);
  g_free(app_dir);

  FILE* file = fopen(path, "w");
  g_free(path);
  if (file == nullptr) {
    return;
  }
  fprintf(file, "{\n");
  if (maximized) {
    fprintf(file, "  \"is_maximized\": true\n");
  } else {
    gint width = 0;
    gint height = 0;
    gtk_window_get_size(window, &width, &height);

    gint x = 0;
    gint y = 0;
    gtk_window_get_position(window, &x, &y);

    fprintf(file, "  \"width\": %d,\n", width);
    fprintf(file, "  \"height\": %d,\n", height);
    fprintf(file, "  \"x\": %d,\n", x);
    fprintf(file, "  \"y\": %d,\n", y);
    fprintf(file, "  \"is_maximized\": false\n");
  }
  fprintf(file, "}\n");
  fclose(file);
}

static gboolean save_window_state_debounced(gpointer data) {
  _save_pending = 0;
  save_window_state(GTK_WINDOW(data));
  return G_SOURCE_REMOVE;
}

static gboolean on_configure_event(GtkWidget* widget, GdkEventConfigure* event) {
  if (gtk_window_is_maximized(GTK_WINDOW(widget))) {
    return FALSE;
  }
  if (_save_pending != 0) {
    g_source_remove(_save_pending);
  }
  _save_pending = g_timeout_add(500, save_window_state_debounced, widget);
  return FALSE;
}

static gboolean on_window_state_event(GtkWidget* widget,
                                      GdkEventWindowState* event) {
  save_window_state(GTK_WINDOW(widget));
  return FALSE;
}

static void on_window_destroy(GtkWidget* widget) {
  save_window_state(GTK_WINDOW(widget));
}

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  load_window_state();

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  gtk_window_set_default_size(window, saved_width, saved_height);
  GdkGeometry hints = {};
  hints.min_width = 1280;
  hints.min_height = 800;
  gtk_window_set_geometry_hints(window, nullptr, &hints, GDK_HINT_MIN_SIZE);

  if (saved_x >= 0 && saved_y >= 0) {
    gtk_window_move(window, saved_x, saved_y);
  }
  if (saved_maximized) {
    gtk_window_maximize(window);
  }

  // If you want to use a header bar, uncomment the following lines.
  // Header bars are commonly used in GNOME based desktop environments and
  // allow additional widgets to be added to the title bar.
  // See https://docs.gtk.org/gtk3/class.HeaderBar.html
  // GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
  // gtk_widget_show(GTK_WIDGET(header_bar));
  // gtk_header_bar_set_show_close_button(header_bar, TRUE);
  // gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));

  gtk_window_set_title(window, "YesPlayMusic");
  // 打包时图标装在 <可执行文件目录>/data/yesplaymusic.png；装进系统的话用主题图标
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  g_autofree gchar* dir = exe ? g_path_get_dirname(exe) : nullptr;
  g_autofree gchar* icon =
      dir ? g_build_filename(dir, "data", "yesplaymusic.png", nullptr) : nullptr;
  if (icon == nullptr || !gtk_window_set_icon_from_file(window, icon, nullptr)) {
    gtk_window_set_icon_name(window, "yesplaymusic");
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#0B0B0D");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect(window, "configure-event", G_CALLBACK(on_configure_event),
                   nullptr);
  g_signal_connect(window, "window-state-event",
                   G_CALLBACK(on_window_state_event), nullptr);
  g_signal_connect(window, "destroy", G_CALLBACK(on_window_destroy), nullptr);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                   gchar*** arguments,
                                                   int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
