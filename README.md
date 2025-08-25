# iOS PWA Shell with ASWebAuthenticationSession

This is a modified iOS PWA (Progressive Web App) shell application that implements secure authentication using `ASWebAuthenticationSession` and provides granular control over URL handling between the webview and external browsers.

## Key Features & Modifications

### 1. ASWebAuthenticationSession Integration
The app intercepts OAuth authentication URLs (specifically Apple Sign-in in this example) and handles them through `ASWebAuthenticationSession` instead of the default webview. This provides:
- More secure authentication flow
- Native iOS authentication UI
- Proper session handling
- Support for biometric authentication when available

### 2. Smart URL Routing
The app intelligently routes URLs based on configurable rules:
- **Internal URLs**: Open within the webview (defined in `allowedUrlPrefixes`)
- **Authentication URLs**: Handled via ASWebAuthenticationSession
- **External URLs**: Open in Safari or default browser
- **Special schemes**: Handle `tel:`, `mailto:` links appropriately

### 3. Custom Callback Scheme
Uses a custom URL scheme for OAuth callbacks, enabling the app to receive authentication responses directly.

## Configuration Guide

### Step 1: Update Settings.swift

```swift
// Update the root URL for your PWA
let rootUrl = URL(string: "https://your-domain.com")!

// Configure allowed origins (domains that open in webview)
let allowedOrigins: [String] = ["your-domain.com"]

// Set your app's custom cookie if needed
let platformCookie = Cookie(name: "app-platform", value: "iOS App Store")
```

### Step 2: Configure URL Prefixes

In [`WebView.swift`](src/Caribbean%20AI/WebView.swift:110-113), update the allowed URL prefixes:

```swift
static let allowedUrlPrefixes: [String] = [
    "https://your-domain.com",
    "https://auth.your-domain.com"  // Add your auth subdomain if applicable
]
```

### Step 3: Set Up Custom URL Scheme

1. **Define your callback scheme** in [`ViewController.swift`](src/Caribbean%20AI/ViewController.swift:156):
```swift
let callbackUrlScheme = "yourappscheme" // Replace with your unique scheme
```

2. **Register the scheme in Info.plist**:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>yourappscheme</string>
        </array>
        <key>CFBundleURLName</key>
        <string>com.yourcompany.yourapp</string>
    </dict>
</array>
```

### Step 4: Configure ASWebAuthenticationSession Trigger

In [`WebView.swift`](src/Caribbean%20AI/WebView.swift:149-151), modify the authentication detection logic for your OAuth provider:

```swift
// Example for generic OAuth provider
if requestUrl.host == "auth.your-domain.com" && 
   requestUrl.path.contains("/authorize") && 
   requestUrl.query?.contains("provider=yourprovider") ?? false {
    // ASWebAuthenticationSession handling code...
}
```

### Step 5: Handle Authentication Callback

The callback handling in [`WebView.swift`](src/Caribbean%20AI/WebView.swift:184-235) needs to be adapted to your authentication flow:

```swift
// Modify the success URL handling
if let successUrl = callbackURL {
    // Extract tokens/params from the callback URL
    guard let fragment = successUrl.fragment else {
        // Handle error
        return
    }
    
    // Construct your target URL with authentication data
    let targetBaseUrl = "https://your-domain.com"
    let targetPath = "/dashboard" // Your post-auth landing page
    let targetUrlString = "\(targetBaseUrl)\(targetPath)#\(fragment)"
    
    // Navigate to the authenticated page
    webView.load(URLRequest(url: URL(string: targetUrlString)!))
}
```

### Step 6: Configure App Bound Domains

Add your domains to `Info.plist` for WKWebView's App Bound Domains:

```xml
<key>WKAppBoundDomains</key>
<array>
    <string>your-domain.com</string>
    <string>auth.your-domain.com</string>
</array>
```

## Implementation Details

### URL Decision Logic Flow

1. **Authentication URLs** → Intercepted and handled via ASWebAuthenticationSession
2. **about:blank** → Allowed immediately
3. **Downloads/Blobs** → Handled by download delegate
4. **User Navigation** (links, forms, history):
   - Internal URLs → Load in webview
   - External URLs → Open in Safari
   - Special schemes (tel, mailto) → System handler
5. **Programmatic Navigation** → Generally allowed (scripts, iframes, etc.)

### Security Features

- **App Bound Domains**: Restricts webview to specified domains
- **Secure Authentication**: OAuth flows handled outside webview
- **Cookie Management**: Custom platform cookies for app identification
- **HTTPS Enforcement**: Ensures secure connections

### PWA Features Included

- **Push Notifications**: Firebase Cloud Messaging integration
- **In-App Purchases**: StoreKit API integration
- **Universal Links**: Deep linking support
- **Offline Support**: Service Worker compatible
- **Pull to Refresh**: Native iOS gesture support
- **Adaptive UI**: Automatic dark/light theme switching

## Testing Your Implementation

### 1. Test Authentication Flow
```swift
// Your auth URL should trigger ASWebAuthenticationSession
// Example: https://auth.your-domain.com/authorize?provider=apple
```

### 2. Test URL Routing
- Internal links should stay in webview
- External links should open in Safari
- Special schemes should trigger appropriate handlers

### 3. Test Callback Handling
- Ensure your custom scheme properly receives callbacks
- Verify token/parameter extraction from callback URLs
- Confirm navigation to authenticated pages

## Troubleshooting

### Common Issues and Solutions

1. **Authentication not triggering**
   - Check URL matching logic in [`decidePolicyFor`](src/Caribbean%20AI/WebView.swift:139-246)
   - Verify your auth URL pattern

2. **Callback not received**
   - Ensure custom scheme is registered in Info.plist
   - Check callback URL scheme matches exactly

3. **Webview navigation issues**
   - Verify allowed URL prefixes
   - Check App Bound Domains configuration

4. **Authentication session not presenting**
   - Ensure `presentationContextProvider` is set
   - Verify view controller implements `ASWebAuthenticationPresentationContextProviding`

## Dependencies

- iOS 13.0+ (for ASWebAuthenticationSession)
- WebKit framework
- AuthenticationServices framework
- Firebase (optional, for push notifications)
- StoreKit (optional, for in-app purchases)

## License

Please refer to the [LICENSE](src/LICENSE) file for licensing information.

## Contributing

When contributing to this project:
1. Test all authentication flows thoroughly
2. Ensure URL routing logic remains intact
3. Update this README with any new configuration requirements
4. Follow existing code patterns and conventions

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review the inline code comments
3. Test with Safari Web Inspector (enabled in debug mode)
4. Ensure all Info.plist configurations are correct