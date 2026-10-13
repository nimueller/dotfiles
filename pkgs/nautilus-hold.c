// Keeps Nautilus running once it has started (home-manager/desktop: the
// nautilus service), so the file chooser and new windows open right away.
// Nautilus quits about ten seconds after its last window closes, and
// GApplication has no setting against that, but a hold taken before it runs
// keeps it alive; "nautilus -q" still quits it.
#define _GNU_SOURCE
#include <dlfcn.h>

int g_application_run(void *app, int argc, char **argv) {
    void (*hold)(void *) = dlsym(RTLD_DEFAULT, "g_application_hold");
    int (*run)(void *, int, char **) = dlsym(RTLD_NEXT, "g_application_run");
    hold(app);
    return run(app, argc, argv);
}
