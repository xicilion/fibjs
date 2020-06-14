/**
 * @author Richard
 * @email ricahrdo2016@mail.com
 * @create date 2020-06-12 04:25:25
 * @modify date 2020-06-12 04:25:25
 * @desc WebView Implementation in OSX
 */

#ifdef __APPLE__

#include <Cocoa/Cocoa.h>
#include <Webkit/Webkit.h>

#include "object.h"
#include "ifs/gui.h"
#include "ifs/fs.h"
#include "ifs/os.h"
#include "path.h"
#include "WebView.h"
#include "EventInfo.h"
#include "utf8.h"
#include <exlib/include/thread.h>

#include "ns-api.h"

namespace fibjs {

void putGuiPool(AsyncEvent* ac)
{
    s_uiPool.putTail(ac);
}

DECLARE_MODULE(gui);

class gui_thread : public exlib::OSThread {
public:
    // Run In GUI Thread, get AsyncEvent from s_uiPool to invoke
    virtual void Run()
    {
        // initialize one fibjs runtime
        Runtime rt(NULL);

        printf("gui_thread->Run 1\n");
        [[NSApplication sharedApplication] setDelegate:[__NSApplicationDelegate new]];
        WebView::setupAppMenubar();

        /**
         * 目前是: 
         * - 另一方面, 关闭窗口后, 从 webview_windowWillClose 回调中执行了 WebView::clear, 之后, 这个 Loop 又开始运行了(如果此时系统中还有 isolate 在运行的话)
         */
        while (true) {
            AsyncEvent* p = s_uiPool.getHead();

            if (p) {
                p->invoke();
            }
            // 从 sharedApplication 的事件循环中中取得事件
            id event = WebView::fetchEventFromNSMainLoop(0);
            if (event)
                [[NSApplication sharedApplication] sendEvent:event];
        }
        printf("gui_thread->Run 2\n");
    }

public:
    // OTHERS
    result_t AddRef(void)
    {
        return 1;
    }
    result_t Release(void)
    {
        return 1;
    }
};

void run_gui()
{
    gui_thread* _thGUI = new gui_thread();

    _thGUI->bindCurrent();
    s_thGUI = _thGUI;

    _thGUI->Run();
    // _thGUI->suspend();
}

// useless for darwin
result_t gui_base::setVersion(int32_t ver)
{
    return 0;
}

// In Javascript Thread
result_t gui_base::open(exlib::string url, v8::Local<v8::Object> opt, obj_ptr<WebView_base>& retVal)
{
    obj_ptr<NObject> o = new NObject();
    o->add(opt);

    obj_ptr<WebView> wv = new WebView(url, o);
    wv->wrap();

    asyncCall(WebView::openWebViewInGUIThread, wv, CALL_E_GUICALL);
    retVal = wv;

    return 0;
};

// Would Call In Javascript Thread
WebView::WebView(exlib::string url, NObject* opt)
{
    printf("[WebView::WebView] before\n");
    holder()->Ref();

    m_url = url;
    m_opt = opt;

    m_title = "[WIP] Darwin WebView";
    m_WinW = 640;
    m_WinH = 400;
    m_bResizable = true;

    m_bDebug = false;

    m_ac = NULL;
    // _onmessage = NULL;
    // _onclose = NULL;

    m_visible = true;

    printf("[WebView::WebView] after\n");
}

WebView::~WebView()
{
    printf("[WebView::]~WebView");
    clear();
}

id WebView::fetchEventFromNSMainLoop(int blocking)
{
    id until = blocking ? [NSDate distantFuture] : [NSDate distantPast];

    return [[NSApplication sharedApplication]
        nextEventMatchingMask:ULONG_MAX
        untilDate:until
        inMode:@"kCFRunLoopDefaultMode"
        dequeue:true
    ];
}

void WebView::webview_exit()
{
    // id app = [NSApplication sharedApplication];
    // [app terminate:app];
}

void WebView::activeNSApp()
{
    m_nsPool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
}

void WebView::setupAppMenubar()
{
    id menubar = [NSMenu alloc];
    [menubar initWithTitle:@""];
    [menubar autorelease];

    id appName = [[NSProcessInfo processInfo] processName];

    id appMenuItem = [NSMenuItem alloc];
    [appMenuItem
        initWithTitle:appName
        action:NULL
        keyEquivalent:get_nsstring("")
    ];

    id appMenu = [NSMenu alloc];
    [appMenu initWithTitle:appName];
    [appMenu autorelease];

    [appMenuItem setSubmenu:appMenu];
    [menubar addItem:appMenuItem];

    id title = [get_nsstring("Hide ") stringByAppendingString:appName];
    id item = create_menu_item(title, "hide:", "h");
    [appMenu addItem:item];

    item = create_menu_item(get_nsstring("Hide Others"), "hideOtherApplications:", "h");
    [item setKeyEquivalentModifierMask:(NSEventModifierFlagOption | NSEventModifierFlagCommand)];
    [appMenu addItem:item];

    item = create_menu_item(get_nsstring("Show All"), "unhideAllApplications:", "");
    [appMenu addItem:item];

    [appMenu addItem:[NSMenuItem separatorItem]];

    title = [get_nsstring("Quit ") stringByAppendingString:appName];
    item = create_menu_item(title, "terminate:", "q");
    [appMenu addItem:item];

    [[NSApplication sharedApplication] setMainMenu:menubar];
}

void WebView::onWKWebViewMessage(WKScriptMessage* message)
{
    printf("[WebView::onWKWebViewMessage] 1 \n");

    const char* msg = (const char*)([[message body] UTF8String]);
    // const char* msg = (const char*)objc_msgSend(
    //     objc_msgSend(message, sel_registerName("body")),
    //     sel_registerName("UTF8String")
    // );

    printf("[webview_external_postMessage] view view msg: %s \n", msg);

    // wv->_emit("message", msg);
}

id WebView::getWKPreferences()
{
    Class __WKPreferences
        = objc_allocateClassPair(objc_getClass("WKPreferences"),
            "__WKPreferences", 0);
    objc_property_attribute_t type = { "T", "c" };
    objc_property_attribute_t ownership = { "N", "" };
    objc_property_attribute_t attrs[] = { type, ownership };
    class_replaceProperty(__WKPreferences, "developerExtrasEnabled", attrs, 2);
    objc_registerClassPair(__WKPreferences);

    id wkPreferences = [__WKPreferences new];
    [wkPreferences
        setValue:[NSNumber numberWithBool:!!m_bDebug]
        forKey:[NSString stringWithUTF8String:"developerExtrasEnabled"]
    ];

    return wkPreferences;
}

id WebView::getWKUserContentController()
{
    WKUserContentController* wkUserCtrl = [WKUserContentController new];

    assignToWKUserContentController(wkUserCtrl);

    [wkUserCtrl
        addScriptMessageHandler:[__WKScriptMessageHandler new]
        name:get_nsstring(WEBVIEW_MSG_HANDLER_NAME)
    ];

    WKUserScript* windowExternalOverrideScript = [[WKUserScript alloc]
        initWithSource:@"window.external = this;postMessage = function(arg){ webkit.messageHandlers.invoke.postMessage(arg); };"
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart
        forMainFrameOnly:FALSE
    ];

    [wkUserCtrl addUserScript:windowExternalOverrideScript];

    return wkUserCtrl;
}

id WebView::prepareWKWebViewConfig()
{
    id wkWebViewConfig = [WKWebViewConfiguration new];

    id processPool = [wkWebViewConfig processPool];
    [processPool _setDownloadDelegate:[__WKDownloadDelegate new]];
    [wkWebViewConfig setProcessPool:processPool];
    [wkWebViewConfig setUserContentController:getWKUserContentController()];
    [wkWebViewConfig setPreferences:getWKPreferences()];

    return wkWebViewConfig;
}

void WebView::initWindow()
{
    unsigned int style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
    if (m_bResizable) style = style | NSWindowStyleMaskResizable;

    /* s_activeWinObjcId =  */m_nsWindow = [[NSWindow alloc]
        initWithContentRect:m_webview_window_rect
        styleMask:style
        backing:NSBackingStoreBuffered
        defer:FALSE
    ];

    [m_nsWindow autorelease];

    [m_nsWindow setDelegate:[__NSWindowDelegate new]];
    [m_nsWindow setTitle:[NSString stringWithUTF8String:m_title.c_str()]];

    printf("[WebView::initWindow] assign self to m_nsWindow\n");
    assignToToNSWindow(m_nsWindow);
}

id WebView::getWKWebView()
{
    id webview = [
        [WKWebView alloc]
        initWithFrame:m_webview_window_rect
        configuration:prepareWKWebViewConfig()
    ];

    [webview setUIDelegate:[__WKUIDelegate new]];
    [webview setNavigationDelegate:[__WKNavigationDelegate new]];

    return webview;
}

void WebView::navigateWKWebView()
{
    id nsURL = [NSURL
        URLWithString:get_nsstring(
            webview_check_url(m_url.c_str())
        )
    ];
    [m_wkWebView loadRequest:[NSURLRequest requestWithURL:nsURL]];
}

void WebView::setWKWebViewStyle()
{
    [m_wkWebView setAutoresizesSubviews:TRUE];
    [m_wkWebView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
}

void WebView::activeApp()
{
    id app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    [app finishLaunching];
    [app activateIgnoringOtherApps:YES];
}

int WebView::createWKWebView()
{
    initWindowRect();

    initWindow();

    // make it center
    [m_nsWindow center];

    m_wkWebView = getWKWebView();
    navigateWKWebView();

    setWKWebViewStyle();
    // linkWindowWithWebview
    [[m_nsWindow contentView] addSubview:m_wkWebView];

    // putWindowToTopOrder
    [m_nsWindow orderFrontRegardless];

    activeApp();

    setupAppMenubar();

    // w->priv.should_exit = 0;
    return 0;
}

int WebView::webview_eval(WebView* w, const char* js)
{
    // [w->priv.webview
    //     evaluateJavaScript:get_nsstring(js)
    //     completionHandler:NULL
    // ];

    return 0;
}

int WebView::webview_inject_css(WebView* w, const char* css)
{
    // int n = webview_js_encode(css, NULL, 0);
    // char* esc = (char*)calloc(1, sizeof(CSS_INJECT_FUNCTION) + n + 4);
    // if (esc == NULL) {
    //     return -1;
    // }
    // char* js = (char*)calloc(1, n);
    // webview_js_encode(css, js, n);
    // snprintf(esc, sizeof(CSS_INJECT_FUNCTION) + n + 4, "%s(\"%s\")",
    //     CSS_INJECT_FUNCTION, js);
    // int r = webview_eval(w, esc);
    // free(js);
    // free(esc);
    // return r;

    return 0;
}

void WebView::webview_set_fullscreen(WebView* w, int fullscreen)
{
    // unsigned long windowStyleMask = (unsigned long)[w->priv.window styleMask];
    // int b = (((windowStyleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen)
    //         ? 1
    //         : 0);
    // if (b != fullscreen) {
    //     [w->priv.window toggleFullScreen:NULL];
    // }
}

void WebView::webview_set_color(WebView* w, uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    // id color = [NSColor
    //     colorWithRed:((float)r / 255.0)
    //     green:((float)g / 255.0)
    //     blue:((float)b / 255.0)
    //     alpha:((float)a / 255.0)
    // ];

    // [w->priv.window setBackgroundColor:color];

    // if (0.5 >= ((r / 255.0 * 299.0) + (g / 255.0 * 587.0) + (b / 255.0 * 114.0)) / 1000.0) {
    //     [w->priv.window
    //         setAppearance:[NSAppearance appearanceNamed:get_nsstring("NSAppearanceNameVibrantDark")]
    //     ];
    // } else {
    //     [w->priv.window
    //         setAppearance:[NSAppearance appearanceNamed:get_nsstring("NSAppearanceNameVibrantLight")]
    //     ];
    // }

    // [w->priv.window setOpaque:FALSE];
    // [w->priv.window setTitlebarAppearsTransparent:YES];
}

void WebView::webview_dialog(WebView* w, enum webview_dialog_type dlgtype, int flags, const char* title, const char* arg, char* result, size_t resultsz)
{
    // if (dlgtype == WEBVIEW_DIALOG_TYPE_OPEN || dlgtype == WEBVIEW_DIALOG_TYPE_SAVE) {
    //     id panel = (id)objc_getClass("NSSavePanel");
    //     if (dlgtype == WEBVIEW_DIALOG_TYPE_OPEN) {
    //         id openPanel = [NSOpenPanel openPanel];
            
    //         if (flags & WEBVIEW_DIALOG_FLAG_DIRECTORY) {
    //             [openPanel setCanChooseFiles:FALSE];
    //             [openPanel setCanChooseDirectories:TRUE];
    //         } else {
    //             [openPanel setCanChooseFiles:TRUE];
    //             [openPanel setCanChooseDirectories:FALSE];
    //         }

    //         [openPanel setResolvesAliases:FALSE];
    //         [openPanel setAllowsMultipleSelection:FALSE];
    //         panel = openPanel;
    //     } else {
    //         panel = [NSSavePanel savePanel];
    //     }

    //     [panel setCanCreateDirectories:TRUE];
    //     [panel setShowsHiddenFiles:TRUE];
    //     [panel setExtensionHidden:FALSE];
    //     [panel setCanSelectHiddenExtension:FALSE];
    //     [panel setTreatsFilePackagesAsDirectories:TRUE];

    //     [panel
    //         beginSheetModalForWindow:w->priv.window
    //         completionHandler:^(NSModalResponse result) {
    //             [[NSApplication sharedApplication] stopModalWithCode:result];
    //         }
    //     ];

    //     if (
    //         [[NSApplication sharedApplication] runModalForWindow:panel] == NSModalResponseOK
    //     ) {
    //         id url = [panel URL];
    //         id path = [url path];
    //         const char* filename = (const char*)[path UTF8String];
    //         strlcpy(result, filename, resultsz);
    //     }
    // } else if (dlgtype == WEBVIEW_DIALOG_TYPE_ALERT) {
    //     id a = [NSAlert new];
    //     switch (flags & WEBVIEW_DIALOG_FLAG_ALERT_MASK) {
    //     case WEBVIEW_DIALOG_FLAG_INFO:
    //         [a setAlertStyle:NSAlertStyleInformational];
    //         break;
    //     case WEBVIEW_DIALOG_FLAG_WARNING:
    //         printf("Warning\n");
    //         [a setAlertStyle:NSAlertStyleWarning];
    //         break;
    //     case WEBVIEW_DIALOG_FLAG_ERROR:
    //         printf("Error\n");
    //         [a setAlertStyle:NSAlertStyleCritical];
    //         break;
    //     }

    //     [a setShowsHelp:FALSE];
    //     [a setShowsSuppressionButton:FALSE];
    //     [a setMessageText:get_nsstring(title)];
    //     [a setInformativeText:get_nsstring(arg)];

    //     [a addButtonWithTitle:get_nsstring("OK")];
    //     [a runModal];
    //     [a release];
    // }
}

int WebView::webview_js_encode(const char* s, char* esc, size_t n)
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

id WebView::create_menu_item(id title, const char* action, const char* key)
{    
    id item = [[NSMenuItem alloc]
        initWithTitle:title
        action:sel_registerName(action)
        keyEquivalent:get_nsstring(key)
    ];
    [item autorelease];

    return item;
}

void WebView::clear()
{
    printf("[WebView::clear] \n");
    // if (_onmessage) {
    //     // _onmessage->Release();
    //     _onmessage = NULL;
    // }

    // if (_onclose) {
    //     // _onclose->Release();
    //     _onclose = NULL;
    // }

    if (m_ac) {
        m_ac->post(0);
        m_ac = NULL;
    }
}

result_t WebView::setHtml(exlib::string html, AsyncEvent* ac)
{
    if (ac->isSync())
        return CHECK_ERROR(CALL_E_GUICALL);

    return 0;
}

result_t WebView::print(int32_t mode, AsyncEvent* ac)
{
    if (ac->isSync())
        return CHECK_ERROR(CALL_E_GUICALL);

    return 0;
}

result_t WebView::close(AsyncEvent* ac)
{
    isolate_unref();

    if (ac->isSync())
        return CHECK_ERROR(CALL_E_GUICALL);

    return 0;
}

// static int async_webview_eval(const char* jsscript)
// {
//     WebView* w = WebView::getCurrentWebViewStruct_deprecated();
//     if (w != NULL) {
//         printf("[async_webview_eval] would eval \n");
//         WebView::webview_eval(w, jsscript);
//     }

//     return 0;
// }

result_t WebView::postMessage(exlib::string msg)
{
    // printf("[WebView::postMessage] view view argument %s \n", msg.c_str());

    // WebView* w = WebView::getCurrentWebViewStruct_deprecated();
    // if (w != NULL) {
    //     exlib::string jsstr = "if (this.onmessage) { this.onmessage(";
    //     // TODO: maybe escape here?
    //     jsstr.append("\"");
    //     jsstr.append(msg.c_str());
    //     jsstr.append("\"");
    //     jsstr.append("); }");

    //     printf("[WebView::postMessage] simple WebView::postMessage %s \n", jsstr.c_str());

    //     asyncCall(async_webview_eval, jsstr.c_str(), CALL_E_GUICALL);
    // } else {
    //     printf("[WebView::postMessage] no s_activeWinObjcId, no webview struct \n");
    // }

    return 0;
}

result_t WebView::postMessage(exlib::string msg, AsyncEvent* ac)
{
    if (ac->isSync()) {
        printf("[WebView::postMessage] I would go into CALL_E_GUICALL\n");
        return CHECK_ERROR(CALL_E_GUICALL);
    }

    return postMessage(msg);
}

result_t WebView::get_visible(bool& retVal)
{
    retVal = m_visible;
    return 0;
}

result_t WebView::set_visible(bool newVal)
{
    m_visible = newVal;

    return 0;
}

// ----- Control methods -----

void WebView::GoBack()
{
    // DO REAL THING
    return;
}

void WebView::GoForward()
{
    // DO REAL THING
    return;
}

void WebView::Refresh()
{
    // DO REAL THING
    return;
}

void WebView::Navigate(exlib::string szUrl)
{
    // bstr_t url(UTF8_W(szUrl));
    // variant_t flags(0x02u); //navNoHistory
    // DO REAL THING
    return;
}

result_t WebView::AddRef(void)
{
    Ref();
    return 1;
}

result_t WebView::Release(void)
{
    Unref();
    return 1;
}

extern const wchar_t* g_console_js;
}

#endif /* __APPLE__ */