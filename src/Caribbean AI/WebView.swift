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

        // Check if the navigation is requesting a new window/tab
        // (often indicated by targetFrame being nil for target="_blank" or window.open)
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            print("Target requires new window for URL: \(url.absoluteString). Opening externally.")

            // Check if the application can open the URL scheme (http, https, etc.)
            if UIApplication.shared.canOpenURL(url) {   
                // Open the URL in the default external browser
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            } else {
                print("Cannot open URL externally: \(url.absoluteString)")
                // Handle cases where the URL can't be opened (e.g., custom schemes not configured)
            }
        }

        // Return nil because we are handling the new window request externally
        // and don't want WKWebView to create a new internal web view.
        return nil
    }


    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let requestUrl = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let requestUrlString = requestUrl.absoluteString.lowercased()
        print("➡️ Navigating to: \(requestUrlString) | Type: \(navigationAction.navigationType.rawValue)")

        // --- Check for Apple Sign-in Initiation ---
        // Adjust the host and path check if your specific Apple auth trigger URL is different
        if requestUrl.host == "auth.caribbeans.ai" && requestUrl.path.contains("/authorize") && requestUrl.query?.contains("provider=apple") ?? false {

            print(" intercepted Apple Sign-in URL: \(requestUrlString)")

            // Define your callback URL scheme (must be unique and declared in Info.plist)
            // Example: "yourappscheme"
            let callbackUrlScheme = "caribbeansai" // <-- IMPORTANT: Replace with your actual scheme

            // Cancel the navigation in WKWebView
            decisionHandler(.cancel)

            // Start the ASWebAuthenticationSession
            self.webAuthSession = ASWebAuthenticationSession(url: requestUrl, callbackURLScheme: callbackUrlScheme) { callbackURL, error in
                // --- Handle the callback ---
                if let error = error {
                    print("❌ ASWebAuthenticationSession Error: \(error)")
                    // Handle error appropriately - maybe show an alert or reload the login page
                    // Example: Reload the original page or show error state
                    // DispatchQueue.main.async {
                    //     self.webView.reload()
                    // }
                    if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                        print("User canceled Apple Sign-in")
                        // No need to reload page usually if user explicitly canceled
                    } else {
                         // Handle other errors (network, etc.)
                         // Maybe reload the login page or show an error message
                        DispatchQueue.main.async {
                           let originalLoginURL = URL(string: "https://caribbeans.ai/login")! // Or your specific login page URL
                           self.webView.load(URLRequest(url: originalLoginURL))
                        }
                    }

                    // Inside the ASWebAuthenticationSession completion handler...
                    } else if let successUrl = callbackURL {
                        print("✅ ASWebAuthenticationSession Success URL: \(successUrl)")

                        DispatchQueue.main.async {
                            // Safely unwrap the webView BEFORE trying to use it
                            guard let webView = CaribbeanAI.webView else {
                                print("❌ CaribbeanAI.webView is nil when trying to navigate.")
                                self.webAuthSession = nil // Clear session ref
                                return
                            }

                            // --- Construct the target HTTPS URL ---

                            // 1. Get the fragment (the part after # with the tokens)
                            guard let fragment = successUrl.fragment else {
                                print("❌ Could not get fragment from successURL: \(successUrl)")
                                // Optionally load login page on error
                                let loginUrl = URL(string: "https://caribbeans.ai/login")! // Adjust if needed
                                webView.load(URLRequest(url: loginUrl))
                                self.webAuthSession = nil // Clear session ref
                                return
                            }

                            // 2. Determine the target path. Usually, it's the path from your custom scheme URL.
                            //    For caribbeansai://chat, the path is effectively "/chat".
                            //    If the path could be different, parse it from `successUrl.path`
                            let targetPath = "/chat" // Assuming it's always /chat based on your scheme URL

                            // 3. Construct the final HTTPS URL string
                            //    Replace "caribbeansai://" with your actual web domain "https://caribbeans.ai"
                            let targetBaseUrl = "https://caribbeans.ai" // Make sure this is your correct web app domain
                            let targetUrlString = "\(targetBaseUrl)\(targetPath)#\(fragment)"

                            // 4. Create a URL object
                            guard let targetUrl = URL(string: targetUrlString) else {
                                print("❌ Could not create target HTTPS URL object from string: \(targetUrlString)")
                                // Optionally load login page on error
                                let loginUrl = URL(string: "https://caribbeans.ai/login")! // Adjust if needed
                                webView.load(URLRequest(url: loginUrl))
                                self.webAuthSession = nil // Clear session ref
                                return
                            }

                            // 5. Load the constructed HTTPS URL in the main WebView
                            print("   -> Navigating WKWebView to HTTPS URL with fragment: \(targetUrl)")
                            webView.load(URLRequest(url: targetUrl))

                            // --- End of modification ---

                            self.webAuthSession = nil // Clear session ref after handling
                        }
                    }
                    // ... rest of the completion handler ...
            }

            // Set the presentation context provider (required for iOS 13+)
            self.webAuthSession?.presentationContextProvider = self

            // Start the session
            self.webAuthSession?.start()

            return // Stop further processing in decidePolicyFor
        }

        // --- Existing logic for about:blank, downloads, internal/external checks ---
        // (Keep your existing logic below this point for other navigation types)

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
