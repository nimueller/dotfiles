// Preloaded into Nautilus (home-manager/desktop: the nautilus service).
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <link.h>
#include <string.h>

// Keeps Nautilus running once it has started, so the file chooser and new
// windows open right away. Nautilus quits about ten seconds after its last
// window closes, and GApplication has no setting against that, but a hold
// taken before it runs keeps it alive; "nautilus -q" still quits it.
int g_application_run(void *app, int argc, char **argv) {
    void (*hold)(void *) = dlsym(RTLD_DEFAULT, "g_application_hold");
    int (*run)(void *, int, char **) = dlsym(RTLD_NEXT, "g_application_run");
    hold(app);
    return run(app, argc, argv);
}

// Nautilus is the portal's file chooser, and the portal asks it while
// starting, before it answers anyone. Nautilus' own blocking calls to the
// portal (libadwaita's settings, GTK's portal versions) would start it and
// wait, and both waited 25 seconds for each other, and every Flatpak with
// them. They don't start it here: without a portal they fail at once and
// fall back to GSettings; the portal is started by the calls that don't wait.
#define PORTAL "org.freedesktop.portal.Desktop"
#define G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START 4
#define G_DBUS_CALL_FLAGS_NO_AUTO_START 1

void *g_dbus_proxy_new_for_bus_sync(int bus_type, int flags, void *info, const char *name,
                                    const char *path, const char *iface, void *cancellable,
                                    void **error) {
    void *(*real)(int, int, void *, const char *, const char *, const char *, void *, void **) =
        dlsym(RTLD_NEXT, "g_dbus_proxy_new_for_bus_sync");
    if (name && strcmp(name, PORTAL) == 0)
        flags |= G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START;
    return real(bus_type, flags, info, name, path, iface, cancellable, error);
}

void *g_dbus_connection_call_sync(void *connection, const char *bus_name, const char *path,
                                  const char *iface, const char *method, void *parameters,
                                  void *reply_type, int flags, int timeout, void *cancellable,
                                  void **error) {
    void *(*real)(void *, const char *, const char *, const char *, const char *, void *, void *,
                  int, int, void *, void **) = dlsym(RTLD_NEXT, "g_dbus_connection_call_sync");
    if (bus_name && strcmp(bus_name, PORTAL) == 0)
        flags |= G_DBUS_CALL_FLAGS_NO_AUTO_START;
    return real(connection, bus_name, path, iface, method, parameters, reply_type, flags, timeout,
                cancellable, error);
}

// Apps that name their window "x11:<id>" to the portal (Qt 5 always does,
// even on Wayland) crashed Nautilus 51: it makes its dialog the child of that
// X11 window through Mutter's own protocol, which Hyprland doesn't offer, and
// calls it anyway. strtol(…, 16) in Nautilus itself only reads such ids;
// failing that, Nautilus opens the dialog without a parent instead.
long __isoc23_strtol(const char *s, char **end, int base) {
    long (*real)(const char *, char **, int) = dlsym(RTLD_NEXT, "__isoc23_strtol");
    static struct link_map *nautilus;
    Dl_info caller;
    if (!nautilus)
        dlinfo(dlopen(NULL, RTLD_LAZY), RTLD_DI_LINKMAP, &nautilus);
    if (base == 16 && dladdr(__builtin_return_address(0), &caller) &&
        (ElfW(Addr))caller.dli_fbase == nautilus->l_addr) {
        errno = EINVAL;
        return 0;
    }
    return real(s, end, base);
}
