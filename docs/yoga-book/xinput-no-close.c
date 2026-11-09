/* Preload shim: make XCloseDevice() a no-op for Wine.
 *
 * Wine-staging 11.x (patch 0005-winex11-Keep-track-of-mouse-device-and-pointer-buttons) calls
 * XCloseDevice on the mouse device. On Xwayland that also deletes the XInput 1 event selection
 * Wine's Wintab (tablet) layer made with XSelectExtensionEvent, so Wintab gets one pen event and
 * then none: no pressure, and CSP draws as if with a mouse. WineHQ bug 59772.
 *
 * winex11.so loads libXi with dlopen() and finds XCloseDevice with dlsym(handle, ...), which a
 * plain LD_PRELOAD definition does not intercept, so this library overrides dlsym itself.
 *
 *   gcc -shared -fPIC -O2 -o xinput-no-close.so xinput-no-close.c
 *   LD_PRELOAD=/path/to/xinput-no-close.so wine ...
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>

static int fake_close_device(void *dpy, void *dev)
{
    (void)dpy; (void)dev;
    return 0;
}

void *dlsym(void *handle, const char *name)
{
    static void *(*real_dlsym)(void *, const char *);
    if (!real_dlsym)
        real_dlsym = (void *(*)(void *, const char *))dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
    if (name && !strcmp(name, "XCloseDevice"))
        return (void *)fake_close_device;
    return real_dlsym(handle, name);
}
