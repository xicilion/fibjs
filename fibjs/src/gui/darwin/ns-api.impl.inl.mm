/**
 * @author Richard
 * @email ricahrdo2016@mail.com
 * @create date 2020-06-12 04:25:25
 * @modify date 2020-06-12 04:25:25
 * @desc WebView Implementation in OSX
 */

#ifdef __APPLE__

#import "ns-api.h"

#import "WebView.h"

using fibjs::obj_ptr;
using fibjs::EventInfo;

@implementation __NSApplicationDelegate
-(void)applicationWillTerminate:(id)app
{
    // printf("[webview_applicationWillTerminate] 看看 appDelegate 生效没 \n");
}
-(void)applicationDidFinishLaunching:(id)app
{
    // printf("[webview_applicationDidFinishLaunching] 看看 appDelegate 生效没\n");
}
-(int)applicationShouldTerminate:(id)app
{
    // printf("[webview_applicationShouldTerminate] 看看 appDelegate 生效没 \n");
    // NSTerminateNow = 1
    // NSTerminateLater = 2
    return 1;
}
-(bool)applicationShouldTerminateAfterLastWindowClosed:(id)app
{
    // printf("[webview_applicationShouldTerminateAfterLastWindowClosed] 看看 appDelegate 生效没 \n");
    return false;
}
@end

@implementation __NSWindowDelegate
-(void)windowWillClose:(NSNotification *)willCloseNotification
{
    NSWindow *currentWindow = willCloseNotification.object;
    fibjs::WebView* wv = fibjs::WebView::getWebViewFromNSWindow(currentWindow);

    if (wv != NULL)
        wv->onNSWindowClose();
}
-(void)windowDidMove:(NSNotification *)didMoveNotification
{
    NSWindow *currentWindow = didMoveNotification.object;
    fibjs::WebView* wv = fibjs::WebView::getWebViewFromNSWindow(currentWindow);

    if (wv == NULL)
        return;

    printf("[onWindowDidMove]\n");

    obj_ptr<EventInfo> ei = new EventInfo(wv, "move");
    wv->_emit("move", ei);
}
-(bool)windowShouldClose:(id)window
{
    printf("[webview_windowShouldClose] 看看 winDelegate 生效没 \n");

    id alert = [NSAlert new];
    [alert setAlertStyle:NSAlertStyleWarning];
    [alert setMessageText:get_nsstring("确定退出吗?")];
    [alert addButtonWithTitle:get_nsstring("退出")];
    [alert addButtonWithTitle:get_nsstring("取消")];

    // unsigned long result = (unsigned long)[alert runModal];
    // [alert release];

    // if (result != NSAlertFirstButtonReturn) {
    //     return NO;
    // }

    return YES;
}
@end

@implementation __WKScriptMessageHandler
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message
{
    fibjs::WebView* wv = fibjs::WebView::getWebViewFromWKUserContentController(userContentController);

    if (wv == NULL)
        return;

    const char* wkScriptName = [[message name] UTF8String];
    if (!strcmp(wkScriptName, WEBVIEW_MSG_HANDLER_NAME_INVOKE)) {
        wv->onWKWebViewPostMessage(message);
    } else if (!strcmp(wkScriptName, WEBVIEW_MSG_HANDLER_NAME_INWARD)) {
        wv->onWKWebViewInwardMessage(message);
    }
}
@end

@implementation __WKUIDelegate
// run_open_panel
-(void)webView:(WKWebView *)webView 
runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters 
initiatedByFrame:(WKFrameInfo *)frame 
completionHandler:(void (^)(NSArray<NSURL *> *URLs))completionHandler
{
    id openPanel = [NSOpenPanel openPanel];
    [openPanel setAllowsMultipleSelection:[parameters allowsMultipleSelection]];
    [openPanel setCanChooseFiles:1];
    [openPanel
        beginWithCompletionHandler:^(NSInteger result) {
            if (result == NSModalResponseOK) {
                completionHandler([openPanel URLs]);
            } else {
                completionHandler(nil);
            }
        }];
}

// run_alert_panel
-(void)webView:(WKWebView *)webView 
runJavaScriptAlertPanelWithMessage:(NSString *)message 
initiatedByFrame:(WKFrameInfo *)frame 
completionHandler:(void (^)(void))completionHandler
{
    id alert = [NSAlert new];
    
    [alert setIcon:[NSImage imageNamed:@"NSCaution"]];
    
    [alert setShowsHelp:FALSE];
    [alert setInformativeText:message];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
    [alert release];
    completionHandler();
}

// run_confirmation_panel
-(void)webView:(WKWebView *)webView 
runJavaScriptConfirmPanelWithMessage:(NSString *)message 
initiatedByFrame:(WKFrameInfo *)frame 
completionHandler:(void (^)(BOOL result))completionHandler;
{
    id alert = [NSAlert new];

    [alert setIcon:[NSImage imageNamed:@"NSCaution"]];
    
    [alert setShowsHelp:FALSE];
    [alert setInformativeText:message];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        completionHandler(true);
    } else {
        completionHandler(false);
    }
    [alert release];
    objc_msgSend(alert, sel_registerName("release"));
}
@end

@implementation __WKNavigationDelegate
- (void)webView:(WKWebView *)webView 
decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse 
decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler
{
    if ([navigationResponse canShowMIMEType] == 0) {
        // decisionHandler(WKNavigationActionPolicyDownload);
        decisionHandler(WKNavigationResponsePolicyCancel);
    } else {
        decisionHandler(WKNavigationResponsePolicyAllow);
    }
}
@end

@implementation __WKDownloadDelegate
/***
    _WKDownloadDelegate is an undocumented/private protocol with methods called
    from WKNavigationDelegate
    References:
    https://github.com/WebKit/webkit/blob/master/Source/WebKit/UIProcess/API/Cocoa/_WKDownload.h
    https://github.com/WebKit/webkit/blob/master/Source/WebKit/UIProcess/API/Cocoa/_WKDownloadDelegate.h
    https://github.com/WebKit/webkit/blob/master/Tools/TestWebKitAPI/Tests/WebKitCocoa/Download.mm
***/
- (void)download:(NSURLDownload *)download 
decideDestinationWithSuggestedFilename:(NSString *)filename
completionHandler:(void (^)(int allowOverwrite, id destination))completionHandler
{
    id savePanel = [NSSavePanel savePanel];
    [savePanel setCanCreateDirectories:YES];
    [savePanel setNameFieldStringValue:filename];

    [savePanel
        beginWithCompletionHandler:^(NSModalResponse result) {
            if (result == NSModalResponseOK) {
                id url = objc_msgSend(savePanel, sel_registerName("URL"));
                id path = objc_msgSend(url, sel_registerName("path"));
                completionHandler(1, path);
            } else {
                completionHandler(NO, nil);
            }
        }
    ];
}

- (void)download:(NSURLDownload *)download 
didFailWithError:(NSError *)error
{
    
    printf("%s",
        (const char*)[[error localizedDescription] UTF8String]
    );
}
@end

#endif // __APPLE__