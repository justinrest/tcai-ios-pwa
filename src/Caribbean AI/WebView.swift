import UIKit
import WebKit
import AuthenticationServices
import SafariServices


func createWebView(container: UIView, WKSMH: WKScriptMessageHandler, WKND: WKNavigationDelegate, NSO: NSObject, VC: ViewController) -> WKWebView{

    let config = WKWebViewConfiguration()
    let userContentController = WKUserContentController()

    userContentController.add(WKSMH, name: "print")
    userContentController.add(WKSMH, name: "push-subscribe")
    userContentController.add(WKSMH, name: "push-permission-request")
    userContentController.add(WKSMH, name: "push-permission-state")
    userContentController.add(WKSMH, name: "push-token")
    userContentController.add(WKSMH, name: "iap-products-request")
    userContentController.add(WKSMH, name: "iap-purchase-request")
    userContentController.add(WKSMH, name: "iap-transactions-request")
    userContentController.add(WKSMH, name: "iap-set-uuid-request")
    userContentController.add(WKSMH, name: "haptic")

    config.userContentController = userContentController

    config.limitsNavigationsToAppBoundDomains = true;
    config.allowsInlineMediaPlayback = true
    config.preferences.javaScriptCanOpenWindowsAutomatically = true
    config.preferences.setValue(true, forKey: "standalone")
    
    let webView = WKWebView(frame: calcWebviewFrame(webviewView: container, toolbarView: nil), configuration: config)
    
    setCustomCookie(webView: webView)
    
    webView.uiDelegate = VC
    webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    webView.isHidden = true;

    webView.navigationDelegate = WKND

    webView.scrollView.bounces = false
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    webView.allowsBackForwardNavigationGestures = true
    
    let deviceModel = UIDevice.current.model
    let osVersion = UIDevice.current.systemVersion
    webView.configuration.applicationNameForUserAgent = "Safari/604.1"
    webView.customUserAgent = "Mozilla/5.0 (\(deviceModel); CPU \(deviceModel) OS \(osVersion.replacingOccurrences(of: ".", with: "_")) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(osVersion) Mobile/15E148 Safari/604.1 PWAShell"

    webView.addObserver(NSO, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: NSKeyValueObservingOptions.new, context: nil)
    
    #if DEBUG
    if #available(iOS 16.4, *) {
        webView.isInspectable = true
    }
    #endif
    
    return webView
}

func setAppStoreAsReferrer(contentController: WKUserContentController) {
    let scriptSource = "document.referrer = `app-info://platform/ios-store`;"
    let script = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    contentController.addUserScript(script);
}

func setCustomCookie(webView: WKWebView) {
    let _platformCookie = HTTPCookie(properties: [
        .domain: rootUrl.host!,
        .path: "/",
        .name: platformCookie.name,
        .value: platformCookie.value,
        .secure: "FALSE",
        .expires: NSDate(timeIntervalSinceNow: 31556926)
    ])!

    webView.configuration.websiteDataStore.httpCookieStore.setCookie(_platformCookie)

}

func calcWebviewFrame(webviewView: UIView, toolbarView: UIToolbar?) -> CGRect{
    if ((toolbarView) != nil) {
        return CGRect(x: 0, y: toolbarView!.frame.height, width: webviewView.frame.width, height: webviewView.frame.height - toolbarView!.frame.height)
    }
    else {
        let winScene = UIApplication.shared.connectedScenes.first
        let windowScene = winScene as! UIWindowScene
        var statusBarHeight = windowScene.statusBarManager?.statusBarFrame.height ?? 0

        switch displayMode {
        case "fullscreen":
            #if targetEnvironment(macCatalyst)
                if let titlebar = windowScene.titlebar {
                    titlebar.titleVisibility = .hidden
                    titlebar.toolbar = nil
                }
            #endif
            return CGRect(x: 0, y: 0, width: webviewView.frame.width, height: webviewView.frame.height)
        default:
            #if targetEnvironment(macCatalyst)
            statusBarHeight = 29
            #endif
            let windowHeight = webviewView.frame.height - statusBarHeight
            return CGRect(x: 0, y: statusBarHeight, width: webviewView.frame.width, height: windowHeight)
        }
    }
}

extension ViewController: WKDownloadDelegate {
    // redirect new tabs to main webview
    static let allowedUrlPrefixes: [String] = [
        "https://caribbeans.ai",
        "https://auth.caribbeans.ai"
    ]

    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {

        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            // Google OAuth opens accounts.youtube.com/accounts/SetSID (and similar) as a
            // popup for cookie syncing. These are a side-effect of the OAuth flow and must
            // NOT be sent to Safari — doing so breaks the flow and shows the user a random URL.
            let googleAccountHosts = ["accounts.google.com", "accounts.youtube.com", "accounts.googlevideo.com"]
            if let host = url.host, googleAccountHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                print("Silently ignoring Google OAuth popup: \(url.absoluteString)")
                return nil
            }

            print("Target requires new window for URL: \(url.absoluteString). Opening externally.")
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            } else {
                print("Cannot open URL externally: \(url.absoluteString)")
            }
        }

        return nil
    }


    // Custom URL scheme Supabase redirects to when signing in inside the native app.
    // NOTE: ASWebAuthenticationSession matches this internally and does NOT require it to
    // be registered in Info.plist. The frontend must set redirectTo to "caribbeansai://chat"
    // for every provider it wants handled natively (see app/(auth)/login/page.tsx).
    static let oauthCallbackScheme = "caribbeansai"

    // Runs an OAuth authorize URL in a trusted ASWebAuthenticationSession and routes the
    // caribbeansai:// callback back into the main webview so the web app can finish the session.
    private func startAuthSession(authorizeUrl: URL) {
        let session = ASWebAuthenticationSession(
            url: authorizeUrl,
            callbackURLScheme: Self.oauthCallbackScheme
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }
            self.webAuthSession = nil

            if let error = error {
                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin {
                    print("User canceled sign-in")
                    return
                }
                print("❌ ASWebAuthenticationSession error: \(error)")
                DispatchQueue.main.async {
                    CaribbeanAI.webView?.load(URLRequest(url: URL(string: "https://caribbeans.ai/login")!))
                }
                return
            }

            guard let callbackURL = callbackURL else { return }
            print("✅ OAuth callback: \(callbackURL)")
            DispatchQueue.main.async { self.loadAuthCallback(callbackURL) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.webAuthSession = session
        session.start()
    }

    // Maps caribbeansai://<path>[?query][#fragment] onto its https://caribbeans.ai equivalent
    // and loads it. Handles both Supabase flows: implicit (#access_token=...) and PKCE
    // (?code=...). Tokens are concatenated verbatim so nothing gets re-encoded.
    private func loadAuthCallback(_ callbackURL: URL) {
        guard let webView = CaribbeanAI.webView else { return }

        // In caribbeansai://chat the URL "host" is actually a path word ("chat"); in
        // caribbeansai:///auth/callback the host is empty and the path carries everything.
        let host = callbackURL.host.flatMap { $0.isEmpty ? nil : $0 }
        var path = (host.map { "/" + $0 } ?? "") + callbackURL.path
        if path.isEmpty { path = "/chat" }

        var targetString = "https://caribbeans.ai" + path
        if let query = callbackURL.query, !query.isEmpty {
            targetString += "?" + query
        }
        if let fragment = callbackURL.fragment, !fragment.isEmpty {
            targetString += "#" + fragment
        }

        let target = URL(string: targetString) ?? URL(string: "https://caribbeans.ai/chat")!
        print("   -> Loading \(target)")
        webView.load(URLRequest(url: target))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let requestUrl = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let requestUrlString = requestUrl.absoluteString.lowercased()
        print("➡️ Navigating to: \(requestUrlString) | Type: \(navigationAction.navigationType.rawValue)")

        // --- OAuth via ASWebAuthenticationSession (Google, Apple, Microsoft) ---
        //
        // Supabase OAuth must run in a trusted browser context, not a raw WKWebView:
        // Google and Microsoft reject embedded webviews ("disallowed_useragent"), and
        // the Google flow spawns cookie-sync popups (accounts.youtube.com/SetSID) that
        // would otherwise leak to Safari and break the flow. ASWebAuthenticationSession
        // runs the whole flow in a SafariViewController-grade context and returns via the
        // caribbeansai:// callback scheme.
        //
        // We intercept ANY OAuth authorize navigation and FORCE redirect_to onto the native
        // callback scheme ourselves. This makes the app self-sufficient: Google/Microsoft
        // sign-in works even when the deployed frontend still points OAuth at an https
        // redirect_to (which would otherwise run the whole flow — including the
        // accounts.youtube.com/SetSID popup — inside this WKWebView and dead-end on a white
        // screen). Only OAuth uses /authorize; email/password use /token, so this is safe.
        // "caribbeansai://chat" must be in Supabase's Redirect URLs allowlist (it already is,
        // since Apple sign-in uses it).
        if requestUrl.host == "auth.caribbeans.ai", requestUrl.path.contains("/authorize") {

            print("🔑 Intercepting OAuth via ASWebAuthenticationSession: \(requestUrlString)")
            decisionHandler(.cancel)

            var comps = URLComponents(url: requestUrl, resolvingAgainstBaseURL: false)
            var items = comps?.queryItems ?? []
            items.removeAll { $0.name == "redirect_to" }
            items.append(URLQueryItem(name: "redirect_to", value: "\(Self.oauthCallbackScheme)://chat"))
            comps?.queryItems = items

            startAuthSession(authorizeUrl: comps?.url ?? requestUrl)
            return
        }

        // --- Safety net: any caribbeansai:// redirect that reaches the webview directly ---
        if requestUrl.scheme == Self.oauthCallbackScheme {
            decisionHandler(.cancel)
            DispatchQueue.main.async { self.loadAuthCallback(requestUrl) }
            return
        }

        // --- Existing logic for about:blank, downloads, internal/external checks ---

        // Allow about:blank immediately
        if requestUrl.scheme == "about" {
            decisionHandler(.allow)
            return
        }
        // Handle downloads using the download delegate
        if navigationAction.shouldPerformDownload || requestUrl.scheme == "blob" {
            decisionHandler(.download)
            return
        }

        // Determine if strict internal/external logic should apply
        let isUserLinkOrFormOrHistory = navigationAction.navigationType == .linkActivated ||
                                        navigationAction.navigationType == .formSubmitted ||
                                        navigationAction.navigationType == .formResubmitted ||
                                        navigationAction.navigationType == .backForward ||
                                        navigationAction.navigationType == .reload

        if isUserLinkOrFormOrHistory {
             print("   Checking as potential main navigation...")
             var isInternal = false
             for prefix in Self.allowedUrlPrefixes { // Ensure allowedUrlPrefixes is accessible
                 if requestUrlString.hasPrefix(prefix.lowercased()) {
                     isInternal = true
                     break
                 }
             }

             if isInternal {
                 print("   ✅ Allowing internal user navigation.")
                 decisionHandler(.allow)
                 return
             } else {
                 print("   ❌ External user navigation detected.")
                 // Handle tel/mailto/external http links (Your existing logic)
                 if let scheme = requestUrl.scheme?.lowercased(), ["tel", "mailto"].contains(scheme) {
                     if UIApplication.shared.canOpenURL(requestUrl) {
                         print("       Opening external scheme URL: \(requestUrlString)")
                         UIApplication.shared.open(requestUrl, options: [:], completionHandler: nil)
                     }
                     decisionHandler(.cancel)
                     return
                 }

                 if let scheme = requestUrl.scheme, !scheme.isEmpty, UIApplication.shared.canOpenURL(requestUrl) {
                     print("       Opening non-internal URL in default browser: \(requestUrlString)")
                     UIApplication.shared.open(requestUrl, options: [:], completionHandler: nil)
                 }
                 decisionHandler(.cancel)
                 return
             }
        } else {
            // Allow all other navigation types implicitly
            print("   ✅ Allowing non-user-initiated or '.other' type navigation (likely asset/script/iframe).")
            decisionHandler(.allow)
            return
        }
    }
    
    // Handle javascript: `window.alert(message: String)`
    func webView(_ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void) {

        // Set the message as the UIAlertController message
        let alert = UIAlertController(
            title: nil,
            message: message,
            preferredStyle: .alert
        )

        // Add a confirmation action “OK”
        let okAction = UIAlertAction(
            title: "OK",
            style: .default,
            handler: { _ in
                // Call completionHandler
                completionHandler()
            }
        )
        alert.addAction(okAction)

        // Display the NSAlert
        present(alert, animated: true, completion: nil)
    }
    // Handle javascript: `window.confirm(message: String)`
    func webView(_ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void) {

        // Set the message as the UIAlertController message
        let alert = UIAlertController(
            title: nil,
            message: message,
            preferredStyle: .alert
        )

        // Add a confirmation action “Cancel”
        let cancelAction = UIAlertAction(
            title: "Cancel",
            style: .cancel,
            handler: { _ in
                // Call completionHandler
                completionHandler(false)
            }
        )

        // Add a confirmation action “OK”
        let okAction = UIAlertAction(
            title: "OK",
            style: .default,
            handler: { _ in
                // Call completionHandler
                completionHandler(true)
            }
        )
        alert.addAction(cancelAction)
        alert.addAction(okAction)

        // Display the NSAlert
        present(alert, animated: true, completion: nil)
    }
    // Handle javascript: `window.prompt(prompt: String, defaultText: String?)`
    func webView(_ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void) {

        // Set the message as the UIAlertController message
        let alert = UIAlertController(
            title: nil,
            message: prompt,
            preferredStyle: .alert
        )

        // Add a confirmation action “Cancel”
        let cancelAction = UIAlertAction(
            title: "Cancel",
            style: .cancel,
            handler: { _ in
                // Call completionHandler
                completionHandler(nil)
            }
        )

        // Add a confirmation action “OK”
        let okAction = UIAlertAction(
            title: "OK",
            style: .default,
            handler: { _ in
                // Call completionHandler with Alert input
                if let input = alert.textFields?.first?.text {
                    completionHandler(input)
                }
            }
        )

        alert.addTextField { textField in
            textField.placeholder = defaultText
        }
        alert.addAction(cancelAction)
        alert.addAction(okAction)

        // Display the NSAlert
        present(alert, animated: true, completion: nil)
    }

    func downloadAndOpenFile(url: URL){

        let destinationFileUrl = url
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig)
        let request = URLRequest(url:url)
        let task = session.downloadTask(with: request) { (tempLocalUrl, response, error) in
            if let tempLocalUrl = tempLocalUrl, error == nil {
                if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                    print("Successfully download. Status code: \(statusCode)")
                }
                do {
                    try FileManager.default.copyItem(at: tempLocalUrl, to: destinationFileUrl)
                    self.openFile(url: destinationFileUrl)
                } catch (let writeError) {
                    print("Error creating a file \(destinationFileUrl) : \(writeError)")
                }
            } else {
                print("Error took place while downloading a file. Error description: \(error?.localizedDescription ?? "N/A") ")
            }
        }
        task.resume()
    }

    // func downloadAndOpenBase64File(base64String: String) {
    //     // Split the base64 string to extract the data and the file extension
    //     let components = base64String.components(separatedBy: ";base64,")

    //     // Make sure the base64 string has the correct format
    //     guard components.count == 2, let format = components.first?.split(separator: "/").last else {
    //         print("Invalid base64 string format")
    //         return
    //     }

    //     // Remove the data type prefix to get the base64 data
    //     let dataString = components.last!

    //     if let imageData = Data(base64Encoded: dataString) {
    //         let documentsUrl: URL  =  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    //         let destinationFileUrl = documentsUrl.appendingPathComponent("image.\(format)")

    //         do {
    //             try imageData.write(to: destinationFileUrl)
    //             self.openFile(url: destinationFileUrl)
    //         } catch {
    //             print("Error writing image to file url: \(destinationFileUrl): \(error)")
    //         }
    //     }
    // }

    func openFile(url: URL) {
        self.documentController = UIDocumentInteractionController(url: url)
        self.documentController?.delegate = self
        self.documentController?.presentPreview(animated: true)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                suggestedFilename: String,
                completionHandler: @escaping (URL?) -> Void) {

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(suggestedFilename)

        self.openFile(url: fileURL)
        completionHandler(fileURL)
    }
}
