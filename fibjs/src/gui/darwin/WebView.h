/**
 * @author Richard
 * @email richardo2016@gmail.com
 * @create date 2018-04-23 03:25:07
 * @modify date 2018-04-23 03:25:42
 * @desc WebView Object for Mac OSX
 */
#ifdef __APPLE__

#ifndef WEBVIEW_APPLE_H_
#define WEBVIEW_APPLE_H_

#include "ifs/WebView.h"
#include "EventInfo.h"
#include "lib.h"

namespace fibjs {

const char* WEBVIEW_MSG_HANDLER_NAME = "invoke";

static exlib::LockedList<AsyncEvent> s_uiPool;
static pthread_t s_thread;
class gui_thread;
static gui_thread* s_thGUI;

/**
 * would be called when asyncCall(xx, xx, CALL_E_GUICALL)
 */
void putGuiPool(AsyncEvent* ac)
{
    // printf("putGuiPool\n");
    s_uiPool.putTail(ac);
}

static id s_activeWinObjcId = NULL;

class WebView;

WebView* getClsWebView(struct webview* w)
{
    return (WebView*)w->clsWebView;
}

class WebView : public WebView_base {
    FIBER_FREE();

public:
    WebView(exlib::string url, NObject* opt);
    ~WebView();

    EVENT_SUPPORT();

public:
    // WebView_base
    virtual result_t setHtml(exlib::string html, AsyncEvent* ac);
    virtual result_t print(int32_t mode, AsyncEvent* ac);
    virtual result_t close(AsyncEvent* ac);
    virtual result_t postMessage(exlib::string msg, AsyncEvent* ac);
    virtual result_t get_visible(bool& retVal);
    virtual result_t set_visible(bool newVal);

public:
    EVENT_FUNC(load);
    EVENT_FUNC(move);
    EVENT_FUNC(resize);
    EVENT_FUNC(closed);
    EVENT_FUNC(message);

private:
    void GoBack();
    void GoForward();
    void Refresh();
    void Navigate(exlib::string szUrl);

public:
    result_t AddRef(void);
    result_t Release(void);

public:
    // async call handler & real executation.
    result_t open()
    {
        printf("[WebView::open] before \n");
        m_bSilent = false;
        m_maximize = false;

        if (m_opt) {
        }

        struct webview webview = {};
        webview.title = m_title.c_str();
        webview.url = m_url.c_str();
        webview.width = m_WinW;
        webview.height = m_WinH;
        webview.resizable = m_bResizable;
        webview.debug = m_bDebug;
        webview.clsWebView = this;

        m_webview = &webview;

        objc_nsAppInit(m_webview);
        webview_init(m_webview);

        AddRef();

        // result_t hr = 0;
        // while ((hr = WebView::webview_loop(m_webview, 0)) == 0)
        //     ;

        printf("[WebView::open] after\n");

        return 0;
    }
    static result_t async_open(obj_ptr<fibjs::WebView> w)
    {
        // printf("[WebView::async_open] before \n");
        w->open();
        // printf("[WebView::async_open] after\n");
        return 0;
    }

private:
    void clear();
    result_t postMessage(exlib::string msg);
    // result_t WebView::postClose();

public:
    static id webview_get_event_from_mainloop(int blocking = 0);

    static void send_event_to_sharedApplicatoin_and_check_should_exit(id event);

    static result_t should_exit(struct webview* w)
    {
        return w->priv.should_exit;
    }

    // pure C API about webview
    static int webview_loop(struct webview* w, int blocking)
    {
        id event = WebView::webview_get_event_from_mainloop(blocking);

        WebView::send_event_to_sharedApplicatoin_and_check_should_exit(event);

        return WebView::should_exit(w);
    }

    static int webview_eval(struct webview* w, const char* js)
    {
        [w->priv.webview
            evaluateJavaScript:get_nsstring(js)
            completionHandler:NULL];

        return 0;
    }

    static int webview_inject_css(struct webview* w, const char* css)
    {
        int n = webview_js_encode(css, NULL, 0);
        char* esc = (char*)calloc(1, sizeof(CSS_INJECT_FUNCTION) + n + 4);
        if (esc == NULL) {
            return -1;
        }
        char* js = (char*)calloc(1, n);
        webview_js_encode(css, js, n);
        snprintf(esc, sizeof(CSS_INJECT_FUNCTION) + n + 4, "%s(\"%s\")",
            CSS_INJECT_FUNCTION, js);
        int r = webview_eval(w, esc);
        free(js);
        free(esc);
        return r;
    }

    static void webview_set_fullscreen(struct webview* w, int fullscreen)
    {
        unsigned long windowStyleMask = (unsigned long)objc_msgSend(
            w->priv.window, sel_registerName("styleMask"));
        int b = (((windowStyleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen)
                ? 1
                : 0);
        if (b != fullscreen) {
            objc_msgSend(w->priv.window, sel_registerName("toggleFullScreen:"), NULL);
        }
    }

    static void webview_set_color(struct webview* w, uint8_t r, uint8_t g,
        uint8_t b, uint8_t a)
    {

        id color = objc_msgSend((id)objc_getClass("NSColor"),
            sel_registerName("colorWithRed:green:blue:alpha:"),
            (float)r / 255.0, (float)g / 255.0, (float)b / 255.0,
            (float)a / 255.0);

        objc_msgSend(w->priv.window, sel_registerName("setBackgroundColor:"), color);

        if (0.5 >= ((r / 255.0 * 299.0) + (g / 255.0 * 587.0) + (b / 255.0 * 114.0)) / 1000.0) {
            objc_msgSend(w->priv.window, sel_registerName("setAppearance:"),
                objc_msgSend((id)objc_getClass("NSAppearance"),
                    sel_registerName("appearanceNamed:"),
                    get_nsstring("NSAppearanceNameVibrantDark")));
        } else {
            objc_msgSend(w->priv.window, sel_registerName("setAppearance:"),
                objc_msgSend((id)objc_getClass("NSAppearance"),
                    sel_registerName("appearanceNamed:"),
                    get_nsstring("NSAppearanceNameVibrantLight")));
        }
        objc_msgSend(w->priv.window, sel_registerName("setOpaque:"), 0);
        objc_msgSend(w->priv.window,
            sel_registerName("setTitlebarAppearsTransparent:"), 1);
    }

    static void webview_dialog(struct webview* w,
        enum webview_dialog_type dlgtype, int flags,
        const char* title, const char* arg,
        char* result, size_t resultsz)
    {
        if (dlgtype == WEBVIEW_DIALOG_TYPE_OPEN || dlgtype == WEBVIEW_DIALOG_TYPE_SAVE) {
            id panel = (id)objc_getClass("NSSavePanel");
            if (dlgtype == WEBVIEW_DIALOG_TYPE_OPEN) {
                id openPanel = objc_msgSend((id)objc_getClass("NSOpenPanel"),
                    sel_registerName("openPanel"));
                if (flags & WEBVIEW_DIALOG_FLAG_DIRECTORY) {
                    objc_msgSend(openPanel, sel_registerName("setCanChooseFiles:"), 0);
                    objc_msgSend(openPanel, sel_registerName("setCanChooseDirectories:"),
                        1);
                } else {
                    objc_msgSend(openPanel, sel_registerName("setCanChooseFiles:"), 1);
                    objc_msgSend(openPanel, sel_registerName("setCanChooseDirectories:"),
                        0);
                }
                objc_msgSend(openPanel, sel_registerName("setResolvesAliases:"), 0);
                objc_msgSend(openPanel, sel_registerName("setAllowsMultipleSelection:"),
                    0);
                panel = openPanel;
            } else {
                panel = objc_msgSend((id)objc_getClass("NSSavePanel"),
                    sel_registerName("savePanel"));
            }

            objc_msgSend(panel, sel_registerName("setCanCreateDirectories:"), 1);
            objc_msgSend(panel, sel_registerName("setShowsHiddenFiles:"), 1);
            objc_msgSend(panel, sel_registerName("setExtensionHidden:"), 0);
            objc_msgSend(panel, sel_registerName("setCanSelectHiddenExtension:"), 0);
            objc_msgSend(panel, sel_registerName("setTreatsFilePackagesAsDirectories:"),
                1);
            objc_msgSend(
                panel, sel_registerName("beginSheetModalForWindow:completionHandler:"),
                w->priv.window, ^(id result) {
                    objc_msgSend(objc_msgSend((id)objc_getClass("NSApplication"),
                                    sel_registerName("sharedApplication")),
                        sel_registerName("stopModalWithCode:"), result);
                });

            if (objc_msgSend(objc_msgSend((id)objc_getClass("NSApplication"),
                                sel_registerName("sharedApplication")),
                    sel_registerName("runModalForWindow:"),
                    panel)
                == (id)NSModalResponseOK) {
                id url = objc_msgSend(panel, sel_registerName("URL"));
                id path = objc_msgSend(url, sel_registerName("path"));
                const char* filename = (const char*)objc_msgSend(path, sel_registerName("UTF8String"));
                strlcpy(result, filename, resultsz);
            }
        } else if (dlgtype == WEBVIEW_DIALOG_TYPE_ALERT) {
            id a = objc_msgSend((id)objc_getClass("NSAlert"), sel_registerName("new"));
            switch (flags & WEBVIEW_DIALOG_FLAG_ALERT_MASK) {
            case WEBVIEW_DIALOG_FLAG_INFO:
                objc_msgSend(a, sel_registerName("setAlertStyle:"),
                    NSAlertStyleInformational);
                break;
            case WEBVIEW_DIALOG_FLAG_WARNING:
                printf("Warning\n");
                objc_msgSend(a, sel_registerName("setAlertStyle:"), NSAlertStyleWarning);
                break;
            case WEBVIEW_DIALOG_FLAG_ERROR:
                printf("Error\n");
                objc_msgSend(a, sel_registerName("setAlertStyle:"), NSAlertStyleCritical);
                break;
            }
            objc_msgSend(a, sel_registerName("setShowsHelp:"), 0);
            objc_msgSend(a, sel_registerName("setShowsSuppressionButton:"), 0);
            objc_msgSend(a, sel_registerName("setMessageText:"), get_nsstring(title));
            objc_msgSend(a, sel_registerName("setInformativeText:"), get_nsstring(arg));
            objc_msgSend(a, sel_registerName("addButtonWithTitle:"),
                get_nsstring("OK"));
            objc_msgSend(a, sel_registerName("runModal"));
            objc_msgSend(a, sel_registerName("release"));
        }
    }

    static void webview_print_log(const char* s) { printf("%s\n", s); }

    static void webview_debug(const char* format, ...)
    {
        char buf[4096];
        va_list ap;
        va_start(ap, format);
        vsnprintf(buf, sizeof(buf), format, ap);
        webview_print_log(buf);
        va_end(ap);
    }

    static int webview_js_encode(const char* s, char* esc, size_t n)
    {
        int r = 1; /* At least one byte for trailing zero */
        for (; *s; s++) {
            const unsigned char c = *s;
            if (c >= 0x20 && c < 0x80 && strchr("<>\\'\"", c) == NULL) {
                if (n > 0) {
                    *esc++ = c;
                    n--;
                }
                r++;
            } else {
                if (n > 0) {
                    snprintf(esc, n, "\\x%02x", (int)c);
                    esc += 4;
                    n -= 4;
                }
                r += 4;
            }
        }
        return r;
    }

    static id create_menu_item(id title, const char* action, const char* key)
    {
        id item = objc_msgSend((id)objc_getClass("NSMenuItem"), sel_registerName("alloc"));
        objc_msgSend(item, sel_registerName("initWithTitle:action:keyEquivalent:"),
            title, sel_registerName(action), get_nsstring(key));
        objc_msgSend(item, sel_registerName("autorelease"));

        return item;
    }

    void objc_nsAppInit(struct webview* w);

    id prepareWKPreferences(struct webview* w);

    id getWKUserController(struct webview* w);

    id prepareWKWebViewConfig(struct webview* w);

    void initWindowRect(struct webview* w)
    {
        this->webview_window_rect = CGRectMake(0, 0, w->width, w->height);
    }

    void initWindow(struct webview* w);

    void setupWindowDelegation(struct webview* w);

    void setupWindowTitle(struct webview* w);

    id getWKWebView(struct webview* w);

    void navigateWKWebView(struct webview* w);

    void setWKWebViewStyle(id webview);

    void linkWindowWithWebview(struct webview* w);

    void putWindowToTopOrder(struct webview* w);

    void activeApp();

    void linkAppWithWebView(struct webview* w)
    {
        // id app = objc_msgSend((id)objc_getClass("NSApplication"),
        //     sel_registerName("sharedApplication"));
        // objc_setAssociatedObject(app, "webview", (id)(w), OBJC_ASSOCIATION_ASSIGN);
    }

    int webview_init(struct webview* w)
    {
        initWindowRect(w);

        initWindow(w);
        setupWindowDelegation(w);
        setupWindowTitle(w);

        // make it center
        objc_msgSend(w->priv.window, sel_registerName("center"));

        w->priv.webview = getWKWebView(w);
        navigateWKWebView(w);

        setWKWebViewStyle(w->priv.webview);
        linkWindowWithWebview(w);

        putWindowToTopOrder(w);

        linkAppWithWebView(w);
        activeApp();

        SetupAppMenubar();

        w->priv.should_exit = 0;
        return 0;
    }

    static void webview_terminate(struct webview* w)
    {
        w->priv.should_exit = 1;
    }

    // useless, it means end up sharedApplication.
    void webview_exit()
    {
        id app = objc_msgSend((id)objc_getClass("NSApplication"),
            sel_registerName("sharedApplication"));

        objc_msgSend(app, sel_registerName("terminate:"), app);
    }

public:
    // static registration methods, ONLY run it in GUI Thread
    static void RegNSApplicationDelegations();

    static void SetupAppMenubar()
    {
        id menubar = objc_msgSend((id)objc_getClass("NSMenu"), sel_registerName("alloc"));
        objc_msgSend(menubar, sel_registerName("initWithTitle:"), get_nsstring(""));
        objc_msgSend(menubar, sel_registerName("autorelease"));

        // id appName = objc_msgSend(objc_msgSend((id)objc_getClass("NSProcessInfo"),
        //                               sel_registerName("processInfo")),
        //     sel_registerName("processName"));
        id appName = get_nsstring("喵喵喵");

        id appMenuItem = objc_msgSend((id)objc_getClass("NSMenuItem"), sel_registerName("alloc"));
        objc_msgSend(appMenuItem,
            sel_registerName("initWithTitle:action:keyEquivalent:"), appName,
            NULL, get_nsstring(""));

        id appMenu = objc_msgSend((id)objc_getClass("NSMenu"), sel_registerName("alloc"));
        objc_msgSend(appMenu, sel_registerName("initWithTitle:"), appName);
        objc_msgSend(appMenu, sel_registerName("autorelease"));

        objc_msgSend(appMenuItem, sel_registerName("setSubmenu:"), appMenu);
        objc_msgSend(menubar, sel_registerName("addItem:"), appMenuItem);

        id title = objc_msgSend(get_nsstring("Hide "),
            sel_registerName("stringByAppendingString:"), appName);
        id item = create_menu_item(title, "hide:", "h");
        objc_msgSend(appMenu, sel_registerName("addItem:"), item);

        item = create_menu_item(get_nsstring("Hide Others"),
            "hideOtherApplications:", "h");
        objc_msgSend(item, sel_registerName("setKeyEquivalentModifierMask:"),
            (NSEventModifierFlagOption | NSEventModifierFlagCommand));
        objc_msgSend(appMenu, sel_registerName("addItem:"), item);

        item = create_menu_item(get_nsstring("Show All"), "unhideAllApplications:", "");
        objc_msgSend(appMenu, sel_registerName("addItem:"), item);

        objc_msgSend(appMenu, sel_registerName("addItem:"),
            objc_msgSend((id)objc_getClass("NSMenuItem"),
                sel_registerName("separatorItem")));

        title = objc_msgSend(get_nsstring("Quit "),
            sel_registerName("stringByAppendingString:"), appName);
        item = create_menu_item(title, "terminate:", "q");
        objc_msgSend(appMenu, sel_registerName("addItem:"), item);

        objc_msgSend(objc_msgSend((id)objc_getClass("NSApplication"),
                         sel_registerName("sharedApplication")),
            sel_registerName("setMainMenu:"), menubar);
    }

public:
    static struct webview* getCurrentWebViewStruct()
    {
        if (!s_activeWinObjcId)
            return NULL;

        // printf("s_activeWinObjcId is not NULL \n");

        struct webview* w = (struct webview*)objc_getAssociatedObject(s_activeWinObjcId, "webview");

        return w;
    }
    static WebView* getCurrentWebViewInstance()
    {

        struct webview* w = getCurrentWebViewStruct();
        if (w == NULL)
            return NULL;

        WebView* wv = getClsWebView(w);

        return wv;
    }

public:
    static int on_webview_say_close(struct webview* w)
    {
        WebView* wv = getClsWebView(w);

        if (wv) {
            // wv->postClose();
            wv->_emit("close");

            wv->webview_terminate(w);
            // TODO: use new fiber?
            wv->_emit("closed");

            wv->holder()->Unref();
            wv->clear();
            wv->Release();
        }
        return 0;
    }

    static void onExternalClosed(struct webview* w, const char* arg)
    {
        printf("[onExternalClosed], %s \n", arg);
        WebView* wv = (WebView*)w->clsWebView;
        wv->_emit("closed", arg);
    }

public:
    struct webview* m_webview;

protected:
    exlib::string m_title;
    exlib::string m_url;

    int32_t m_WinW;
    int32_t m_WinH;
    int32_t m_bResizable;
    bool m_bDebug;

    obj_ptr<NObject> m_opt;

    bool m_visible;
    bool m_maximize;
    bool m_bSilent;

    // id webviewid_scriptMessageHandler;
    // id webviewid_downloadDelegate;
    // id webviewid_wkPref;
    // id webviewid_wkUserController;
    // id webviewid_wkwebviewconfig;
    CGRect webview_window_rect;
    // id webviewid_wkwebviewuiDel;
    // id webivewid_wkwebviewnavDel;

    AsyncEvent* m_ac;
};
} /* namespace fibjs */

#endif /* WEBVIEW_APPLE_H_ */
#endif /* __APPLE__ */