import UIKit
import WebKit
import AuthenticationServices
var webView: WKWebView! = nil

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, ASWebAuthenticationPresentationContextProviding, UIDocumentInteractionControllerDelegate, UIScrollViewDelegate {
    var webView: WKWebView!
    var webAuthSession: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return self.view.window ?? ASPresentationAnchor()
    }
    
    var documentController: UIDocumentInteractionController?
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
    
    @IBOutlet weak var loadingView: UIView!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var connectionProblemView: UIImageView!
    @IBOutlet weak var webviewView: UIView!
    var toolbarView: UIToolbar!
    
    var htmlIsLoaded = false;
    var storeKitAPI: StoreKitAPI!
    var refreshControl: UIRefreshControl?
    
    private var themeObservation: NSKeyValueObservation?
    var currentWebViewTheme: UIUserInterfaceStyle = .unspecified

    // Branded startup screen (logo + Libre Baskerville wordmark + spinner),
    // mirroring the Android app. Shown until the first page load completes.
    private var brandedSplash: UIView?

    // Persisted last-session theme key. Startup defaults to DARK and only uses
    // light when the user's previous session resolved to light — same rule as
    // the Android app (see tcaiandroid App.onCreate).
    private static let themeDefaultsKey = "ui_theme"

    // Splash colours mirror the web app's CSS tokens (and the Android splash):
    //   dark  bg #1C1C1C / fg #EDEDED   ·   light bg #FAFAFA / fg #1F1F1F
    private static let splashBackgroundColor = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0x1C / 255.0, green: 0x1C / 255.0, blue: 0x1C / 255.0, alpha: 1)
            : UIColor(red: 0xFA / 255.0, green: 0xFA / 255.0, blue: 0xFA / 255.0, alpha: 1)
    }
    private static let splashForegroundColor = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0xED / 255.0, green: 0xED / 255.0, blue: 0xED / 255.0, alpha: 1)
            : UIColor(red: 0x1F / 255.0, green: 0x1F / 255.0, blue: 0x1F / 255.0, alpha: 1)
    }
    override var preferredStatusBarStyle : UIStatusBarStyle {
        if #available(iOS 13, *), overrideStatusBar{
            if #available(iOS 15, *) {
                return .default
            } else {
                return statusBarTheme == "dark" ? .lightContent : .darkContent
            }
        }
        return .default
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyInitialTheme()
        initWebView()
        initToolbarView()
        loadRootUrl()
        setupBrandedSplash()
        storeKitAPI = StoreKitAPI.init()

        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification , object: nil)

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The window exists by now — assert the saved (default-dark) theme before
        // the web content paints, so the whole shell starts in the right theme.
        applyInitialTheme()
    }

    // MARK: - Branded startup screen + theme rules

    private func savedInterfaceStyle() -> UIUserInterfaceStyle {
        UserDefaults.standard.string(forKey: Self.themeDefaultsKey) == "light" ? .light : .dark
    }

    private func persistTheme(_ style: UIUserInterfaceStyle) {
        guard style != .unspecified else { return }
        UserDefaults.standard.set(style == .light ? "light" : "dark", forKey: Self.themeDefaultsKey)
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
            .first { $0.isKeyWindow }
    }

    // Default to dark (or the last-session theme) before the page loads, so the
    // WebView and chrome start in that theme. adaptiveUIStyle takes over once the
    // page reports its own background colour (see initWebView).
    private func applyInitialTheme() {
        if #available(iOS 15.0, *), adaptiveUIStyle {
            keyWindow()?.overrideUserInterfaceStyle = savedInterfaceStyle()
        }
    }

    private func setupBrandedSplash() {
        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        // The splash always follows the saved/default theme regardless of device.
        overlay.overrideUserInterfaceStyle = savedInterfaceStyle()
        overlay.backgroundColor = Self.splashBackgroundColor

        let logo = UIImageView(image: UIImage(named: "CAILogo") ?? UIImage(named: "LaunchIcon"))
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "Caribbean AI"
        label.textColor = Self.splashForegroundColor
        label.font = UIFont(name: "LibreBaskerville-Bold", size: 26)
            ?? UIFont(name: "Baskerville-Bold", size: 26)
            ?? .boldSystemFont(ofSize: 26)

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = Self.splashForegroundColor
        spinner.startAnimating()

        let stack = UIStackView(arrangedSubviews: [logo, label, spinner])
        stack.axis = .vertical
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(20, after: logo)
        stack.setCustomSpacing(28, after: label)

        overlay.addSubview(stack)
        view.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            logo.widthAnchor.constraint(equalToConstant: 120),
            logo.heightAnchor.constraint(equalToConstant: 120),
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
        ])

        brandedSplash = overlay
    }

    private func hideBrandedSplash() {
        guard let overlay = brandedSplash else { return }
        brandedSplash = nil
        UIView.animate(withDuration: 0.25, animations: { overlay.alpha = 0 }) { _ in
            overlay.removeFromSuperview()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CaribbeanAI.webView.frame = calcWebviewFrame(webviewView: webviewView, toolbarView: nil)
    }
    
    @objc func keyboardWillHide(_ notification: NSNotification) {
        CaribbeanAI.webView.setNeedsLayout()
    }
    
    func initWebView() {
        CaribbeanAI.webView = createWebView(container: webviewView, WKSMH: self, WKND: self, NSO: self, VC: self)
        webviewView.addSubview(CaribbeanAI.webView);
        
        CaribbeanAI.webView.uiDelegate = self;
        
        CaribbeanAI.webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)

        if(pullToRefresh){
            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(self, action: #selector(refreshWebView(_:)), for: UIControl.Event.valueChanged)
            CaribbeanAI.webView.scrollView.addSubview(refreshControl)
            CaribbeanAI.webView.scrollView.bounces = true
            self.refreshControl = refreshControl
            // Own the scroll-view delegate so we can constrain the outer
            // (whole-page) scroll to a top-only pull — see the
            // UIScrollViewDelegate methods below.
            CaribbeanAI.webView.scrollView.delegate = self
        }

        if #available(iOS 15.0, *), adaptiveUIStyle {
            themeObservation = CaribbeanAI.webView.observe(\.underPageBackgroundColor) { [unowned self] webView, _ in
                currentWebViewTheme = CaribbeanAI.webView.underPageBackgroundColor.isLight() ?? true ? .light : .dark
                self.persistTheme(currentWebViewTheme)
                self.overrideUIStyle()
            }
        }
    }

    @objc func refreshWebView(_ sender: UIRefreshControl) {
        CaribbeanAI.webView?.reload()
        sender.endRefreshing()
    }

    // MARK: - Scroll constraints (pull-to-refresh only)
    //
    // The web app owns its own scrolling (fixed chrome + inner scroll areas),
    // so the outer WKWebView scroll view should never move the whole document —
    // its ONLY job is the pull-down-from-the-top gesture that drives
    // pull-to-refresh. Left unconstrained, `bounces = true` lets the page
    // rubber-band in both directions, and after a partial pull the outer scroll
    // view keeps owning the gesture while it settles, which is the "stuck for a
    // few seconds where nothing inside scrolls" state.

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Allow the rubber-band only while at/above the top (negative offset =
        // an active pull-down). Once scrolled into content, kill bouncing so
        // there's no bottom bounce and no floating the whole page around.
        scrollView.bounces = scrollView.contentOffset.y <= 0
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView, willDecelerate decelerate: Bool
    ) {
        // Finger lifted. If this pull didn't commit a refresh, snap straight
        // back to the top instead of letting it slowly rubber-band — that
        // hands the gesture back to the page's inner scroll areas immediately
        // rather than after a multi-second settle.
        guard !(refreshControl?.isRefreshing ?? false) else { return }
        if scrollView.contentOffset.y < 0 {
            scrollView.setContentOffset(.zero, animated: false)
        }
    }

    func createToolbarView() -> UIToolbar{
        let winScene = UIApplication.shared.connectedScenes.first
        let windowScene = winScene as! UIWindowScene
        var statusBarHeight = windowScene.statusBarManager?.statusBarFrame.height ?? 60
        
        #if targetEnvironment(macCatalyst)
        if (statusBarHeight == 0){
            statusBarHeight = 30
        }
        #endif
        
        let toolbarView = UIToolbar(frame: CGRect(x: 0, y: 0, width: webviewView.frame.width, height: 0))
        toolbarView.sizeToFit()
        toolbarView.frame = CGRect(x: 0, y: 0, width: webviewView.frame.width, height: toolbarView.frame.height + statusBarHeight)
//        toolbarView.autoresizingMask = [.flexibleTopMargin, .flexibleRightMargin, .flexibleWidth]
        
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let close = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(loadRootUrl))
        toolbarView.setItems([close,flex], animated: true)
        
        toolbarView.isHidden = true
        
        return toolbarView
    }
    
    func overrideUIStyle(toDefault: Bool = false) {
        if #available(iOS 15.0, *), adaptiveUIStyle {
            if (((htmlIsLoaded && !CaribbeanAI.webView.isHidden) || toDefault) && self.currentWebViewTheme != .unspecified) {
                UIApplication
                    .shared
                    .connectedScenes
                    .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
                    .first { $0.isKeyWindow }?.overrideUserInterfaceStyle = toDefault ? .unspecified : self.currentWebViewTheme;
            }
        }
    }
    
    func initToolbarView() {
        toolbarView =  createToolbarView()
        
        webviewView.addSubview(toolbarView)
    }
    
    @objc func loadRootUrl() {
        CaribbeanAI.webView.load(URLRequest(url: SceneDelegate.universalLinkToLaunch ?? SceneDelegate.shortcutLinkToLaunch ?? rootUrl))
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!){
        htmlIsLoaded = true
        
        self.setProgress(1.0, true)
        self.animateConnectionProblem(false)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            CaribbeanAI.webView.isHidden = false
            self.loadingView.isHidden = true

            self.setProgress(0.0, false)

            self.overrideUIStyle()
            self.hideBrandedSplash()
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        htmlIsLoaded = false;
        
        if (error as NSError)._code != (-999) {
            self.overrideUIStyle(toDefault: true);

            webView.isHidden = true;
            loadingView.isHidden = false;
            animateConnectionProblem(true);
            
            setProgress(0.05, true);

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.setProgress(0.1, true);
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.loadRootUrl();
                }
            }
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

        if (keyPath == #keyPath(WKWebView.estimatedProgress) &&
                CaribbeanAI.webView.isLoading &&
                !self.loadingView.isHidden &&
                !self.htmlIsLoaded) {
                    var progress = Float(CaribbeanAI.webView.estimatedProgress);
                    
                    if (progress >= 0.8) { progress = 1.0; };
                    if (progress >= 0.3) { self.animateConnectionProblem(false); }
                    
                    self.setProgress(progress, true);
        }
    }
    
    func setProgress(_ progress: Float, _ animated: Bool) {
        self.progressView.setProgress(progress, animated: animated);
    }
    
    
    func animateConnectionProblem(_ show: Bool) {
        if (show) {
            self.connectionProblemView.isHidden = false;
            self.connectionProblemView.alpha = 0
            UIView.animate(withDuration: 0.7, delay: 0, options: [.repeat, .autoreverse], animations: {
                self.connectionProblemView.alpha = 1
            })
        }
        else {
            UIView.animate(withDuration: 0.3, delay: 0, options: [], animations: {
                self.connectionProblemView.alpha = 0 // Here you will get the animation you want
            }, completion: { _ in
                self.connectionProblemView.isHidden = true;
                self.connectionProblemView.layer.removeAllAnimations();
            })
        }
    }
        
    deinit {
        CaribbeanAI.webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
    }
}

extension UIColor {
    // Check if the color is light or dark, as defined by the injected lightness threshold.
    // Some people report that 0.7 is best. I suggest to find out for yourself.
    // A nil value is returned if the lightness couldn't be determined.
    func isLight(threshold: Float = 0.5) -> Bool? {
        let originalCGColor = self.cgColor

        // Now we need to convert it to the RGB colorspace. UIColor.white / UIColor.black are greyscale and not RGB.
        // If you don't do this then you will crash when accessing components index 2 below when evaluating greyscale colors.
        let RGBCGColor = originalCGColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)
        guard let components = RGBCGColor?.components else {
            return nil
        }
        guard components.count >= 3 else {
            return nil
        }

        let brightness = Float(((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000)
        return (brightness > threshold)
    }
}

extension ViewController {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
            case "print":
                printView(webView: CaribbeanAI.webView)
            case "push-subscribe":
                handleSubscribeTouch(message: message)
            case "push-permission-request":
                handlePushPermission()
            case "push-permission-state":
                handlePushState()
            case "push-token":
                handleFCMToken()
            case "haptic":
                handleHapticFeedback(message: message)
            case "iap-products-request":
                Task {
                    do {
                        await storeKitAPI.fetchProducts(productIDs: message.body as! [String])
                    }
                }
            case "iap-purchase-request":
            Task {
                if let messageBody = message.body as? String {
                    // Convert the message body to Data.
                    if let data = messageBody.data(using: .utf8) {
                        do {
                            // Convert the data to a dictionary.
                            if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                                // Extract and print the productID and quantity.
                                if let productID = jsonObject["productID"] as? String {
                                    let quantity = jsonObject["quantity"] as? Int ?? 1;
                                    let userUUID = jsonObject["userUUID"] as? String;
                                    
                                    do {
                                        try await storeKitAPI.purchaseProduct(productID: productID, quantity: quantity, userUUID: userUUID)
                                        returnPurchaseResult(state: "success")
                                    } catch StoreKitAPI.ProductError.productNotFound {
                                        returnPurchaseResult(state: "notFound")
                                    } catch StoreKitAPI.ProductError.userCanceled{
                                        returnPurchaseResult(state: "canceled")
                                    } catch {
                                        returnPurchaseResult(state: "failed")
                                    }
                                }
                                else { returnPurchaseResult(state: "failed")  }
                            }
                        } catch {
                            returnPurchaseResult(state: "failed")
                        }
                    }
                }
            }
            case "iap-transactions-request":
                Task {
                    do {
                        await storeKitAPI.fetchActiveTransactions()
                    }
                }
              case "iap-set-uuid-request":
                  Task {
                      if let messageBody = message.body as? String {
                          // Convert the message body to Data.
                          if let data = messageBody.data(using: .utf8) {
                              do {
                                  // Convert the data to a dictionary.
                                  if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                                      // Extract and print the productID and quantity.
                                      if let userUUID = jsonObject["userUUID"] as? String {
                                          do {
                                              await storeKitAPI.listenToPurchaseIntents(userUUID: userUUID)
                                          }
                                      }
                                  }
                              }catch {
                                  print("Error parse JSON or listenToPurchaseIntents: \(error)")
                              }
                          }
                      }
                  }
            default:
                break
            }
    }
}
