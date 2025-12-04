import SwiftUI
import WebKit
import UIKit
import StoreKit

/// Конфигурация для отображения веб-контента
public struct ContentDisplayView: UIViewRepresentable {
    let urlString: String
    let allowsGestures: Bool
    let enableRefresh: Bool
    
    public init(urlString: String, allowsGestures: Bool = true, enableRefresh: Bool = true) {
        self.urlString = urlString
        self.allowsGestures = allowsGestures
        self.enableRefresh = enableRefresh
    }
    
    public func makeUIView(context: Context) -> WKWebView {
        let galaxyConfig = WKWebViewConfiguration()
        let galaxyPreferences = WKWebpagePreferences()
        
        // Настройка JavaScript
        galaxyPreferences.allowsContentJavaScript = true
        galaxyConfig.defaultWebpagePreferences = galaxyPreferences
        galaxyConfig.preferences.javaScriptCanOpenWindowsAutomatically = true
        // Настройка медиа
        galaxyConfig.allowsInlineMediaPlayback = true
        galaxyConfig.mediaTypesRequiringUserActionForPlayback = []
        galaxyConfig.allowsAirPlayForMediaPlayback = true
        galaxyConfig.allowsPictureInPictureMediaPlayback = true
        
        // Настройка данных сайта
        galaxyConfig.websiteDataStore = WKWebsiteDataStore.default()
        
        // Создание WebView
        let galaxyView = WKWebView(frame: .zero, configuration: galaxyConfig)
        
        // Настройка фона (черный)
        galaxyView.backgroundColor = .black
        galaxyView.scrollView.backgroundColor = .black
        galaxyView.isOpaque = false
        
        // Настройка жестов
        galaxyView.allowsBackForwardNavigationGestures = allowsGestures
        
        // Используем Desktop Safari User Agent для прохождения Google OAuth
        // Desktop версия обходит блокировку "embedded browsers"
        galaxyView.customUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        
        // Настройка координатора
        galaxyView.navigationDelegate = context.coordinator
        galaxyView.uiDelegate = context.coordinator
        
        // Настройка refresh control
        let galaxyRefreshControl = UIRefreshControl()
        galaxyRefreshControl.tintColor = .white
        galaxyRefreshControl.addTarget(context.coordinator, action: #selector(context.coordinator.refreshContent(_:)), for: .valueChanged)
        galaxyView.scrollView.refreshControl = galaxyRefreshControl
        
        // Сохраняем ссылки в координаторе
        context.coordinator.galaxyWVView = galaxyView
        context.coordinator.galaxyRefreshControl = galaxyRefreshControl
        
        if let url = URL(string: urlString) {
            galaxyView.load(URLRequest(url: url))
        }
        
        return galaxyView
    }
    
    public func updateUIView(_ uiView: WKWebView, context: Context) {
        // ⚠️ НЕ перезагружаем на каждый апдейт SwiftUI
        // Загружаем только если реально сменился URL
        if uiView.url?.absoluteString != urlString, let url = URL(string: urlString) {
            uiView.load(URLRequest(url: url))
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: ContentDisplayView
        weak var galaxyWVView: WKWebView?
        weak var galaxyRefreshControl: UIRefreshControl?
        var oauthWebView: WKWebView? // Временный WebView для OAuth (deprecated)
        
        // MARK: -- Popup Management
        
        /// Словарь открытых popup WebView и их контроллеров
        private var popupControllers: [WKWebView: PopupWebViewController] = [:]
        
        init(_ parent: ContentDisplayView) {
            self.parent = parent
            super.init()
            
            // Настройка observers для всех событий клавиатуры
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillShowGalaxy),
                name: UIResponder.keyboardWillShowNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardDidShowGalaxy),
                name: UIResponder.keyboardDidShowNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillHideGalaxy),
                name: UIResponder.keyboardWillHideNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardDidHideGalaxy),
                name: UIResponder.keyboardDidHideNotification,
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func refreshContent(_ sender: UIRefreshControl) {
            galaxyWVView?.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.galaxyRefreshControl?.endRefreshing()
            }
        }
        
        // MARK: - Keyboard Handling
        
        // Мягкий viewport refresh без изменения DOM
        private func softViewportRefreshGalaxy() {
            guard let galaxyWebView = galaxyWVView else { return }
            
            // Легкий JavaScript - только события, без изменения DOM
            let galaxyJavaScript = """
            (function() {
                // Триггер viewport и window resize событий
                if (window.visualViewport) {
                    window.dispatchEvent(new Event('resize'));
                }
                window.dispatchEvent(new Event('resize'));
                
                // Легкий scroll для триггера reflow
                window.scrollBy(0, 1);
                window.scrollBy(0, -1);
            })();
            """
            
            galaxyWebView.evaluateJavaScript(galaxyJavaScript, completionHandler: nil)
            
            // Легкий нативный scroll
            let currentOffset = galaxyWebView.scrollView.contentOffset
            galaxyWebView.scrollView.setContentOffset(
                CGPoint(x: currentOffset.x, y: currentOffset.y + 1),
                animated: false
            )
            galaxyWebView.scrollView.setContentOffset(currentOffset, animated: false)
        }
        
        @objc private func keyboardWillShowGalaxy(_ notification: Notification) {
            softViewportRefreshGalaxy()
        }
        
        @objc private func keyboardDidShowGalaxy(_ notification: Notification) {
            // Отложенный refresh после полного показа клавиатуры
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.softViewportRefreshGalaxy()
            }
        }
        
        @objc private func keyboardWillHideGalaxy(_ notification: Notification) {
            softViewportRefreshGalaxy()
        }
        
        @objc private func keyboardDidHideGalaxy(_ notification: Notification) {
            // Немедленный refresh
            softViewportRefreshGalaxy()
            
            // Вторая попытка после задержки
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.softViewportRefreshGalaxy()
            }
            
            // Третья попытка после длинной задержки для упорных случаев
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.softViewportRefreshGalaxy()
            }
        }
        
        // Обработка навигации
        public func webView(_ webView: WKWebView,
                            decidePolicyFor action: WKNavigationAction,
                            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            
            print("📋 [POLICY] ========================================")
            print("📋 [POLICY] Принимаем решение о навигации")
            print("📋 [POLICY] URL: \(action.request.url?.absoluteString ?? "nil")")
            print("📋 [POLICY] Это временный WebView?: \(webView == oauthWebView)")
            print("📋 [POLICY] Это popup WebView?: \(popupControllers[webView] != nil)")
            print("📋 [POLICY] Это главный WebView?: \(webView == galaxyWVView)")
            print("📋 [POLICY] targetFrame: \(action.targetFrame == nil ? "nil (popup/new window)" : "exists (same window)")")
            print("📋 [POLICY] navigationType: \(action.navigationType.rawValue)")
            
            if let url = action.request.url {
                let urlString = url.absoluteString
                
                // Проверяем, это popup WebView?
                if popupControllers[webView] != nil {
                    print("🪟 [POLICY] Это popup WebView, разрешаем навигацию внутри него")
                    // Popup WebView может свободно навигировать
                    // НЕ перенаправляем в главный WebView!
                }
                
                // Legacy: Если это старый временный WebView - перехватываем URL
                else if webView == oauthWebView {
                    print("🔍 [POLICY] Это старый временный WebView! URL: \(urlString)")
                    if !urlString.isEmpty && 
                       urlString != "about:blank" &&
                       !urlString.hasPrefix("about:") {
                        print("✅ [POLICY] URL валидный! Переносим в основной WebView и отменяем навигацию")
                        // Загружаем в основной WebView
                        if let mainWebView = galaxyWVView {
                            mainWebView.load(URLRequest(url: url))
                            oauthWebView = nil
                            print("🔄 [POLICY] Временный WebView уничтожен (oauthWebView = nil)")
                        }
                        decisionHandler(.cancel)
                        return
                    } else {
                        print("⏭️ [POLICY] URL игнорируется (пустой или about:), разрешаем навигацию")
                    }
                }
                
                let scheme = url.scheme?.lowercased()
                print("🔗 [POLICY] Scheme: \(scheme ?? "nil")")
                
                // Открываем внешние схемы в системе
                if let scheme = scheme,
                   scheme != "http", scheme != "https", scheme != "about" {
                    print("🌐 [POLICY] Внешняя схема '\(scheme)', открываем в системе")
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    decisionHandler(.cancel)
                    return
                }
                
                // OAuth popup - загружаем в том же WebView (со свайпом назад)
                if action.targetFrame == nil {
                    print("🪟 [POLICY] targetFrame = nil (popup), загружаем в текущем WebView")
                    webView.load(URLRequest(url: url))
                    decisionHandler(.cancel)
                    return
                }
            }
            
            print("✅ [POLICY] Разрешаем навигацию (.allow)")
            print("📋 [POLICY] ========================================")
            decisionHandler(.allow)
        }
        
        // Обработка дочерних окон - создаем модальный popup WebView
        public func webView(_ webView: WKWebView,
                            createWebViewWith configuration: WKWebViewConfiguration,
                            for navAction: WKNavigationAction,
                            windowFeatures: WKWindowFeatures) -> WKWebView? {
            
            print("🪟 [POPUP] ========================================")
            print("🪟 [POPUP] Попытка открыть новое окно")
            print("🪟 [POPUP] URL: \(navAction.request.url?.absoluteString ?? "nil")")
            print("🪟 [POPUP] HTTP Method: \(navAction.request.httpMethod ?? "nil")")
            print("🪟 [POPUP] Has HTTP Body: \(navAction.request.httpBody != nil)")
            print("🪟 [POPUP] targetFrame: \(navAction.targetFrame == nil ? "nil" : "exists")")
            print("🪟 [POPUP] navigationType: \(navAction.navigationType.rawValue)")
            print("🪟 [POPUP] ========================================")
            
            // Создаем НОВЫЙ ВИДИМЫЙ WebView для popup
            print("🔧 [POPUP] Создаем модальный popup WebView")
            
            // Настраиваем конфигурацию для popup
            configuration.websiteDataStore = WKWebsiteDataStore.default()
            
            // Создаем WebView с такими же настройками как главный
            let popupWebView = WKWebView(frame: .zero, configuration: configuration)
            popupWebView.navigationDelegate = self
            popupWebView.uiDelegate = self
            popupWebView.backgroundColor = .black
            popupWebView.scrollView.backgroundColor = .black
            popupWebView.isOpaque = false
            popupWebView.allowsBackForwardNavigationGestures = parent.allowsGestures
            popupWebView.customUserAgent = webView.customUserAgent
            
            // Создаем контроллер для модального показа
            let popupController = PopupWebViewController(webView: popupWebView, coordinator: self)
            
            // Сохраняем ссылку на popup
            popupControllers[popupWebView] = popupController
            print("💾 [POPUP] Popup сохранен в словаре. Всего popup'ов: \(popupControllers.count)")
            
            // Показываем модально
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let windowScene = UIApplication.shared.connectedScenes
                        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                      let rootVC = windowScene.windows.first?.rootViewController else {
                    print("❌ [POPUP] Не удалось найти rootViewController")
                    return
                }
                
                // Находим топовый presented контроллер
                var topVC = rootVC
                while let presented = topVC.presentedViewController {
                    topVC = presented
                }
                
                print("🎬 [POPUP] Показываем popup модально")
                topVC.present(popupController, animated: true) {
                    print("✅ [POPUP] Popup успешно показан")
                }
            }
            
            // Если есть URL - загружаем его сразу
            if let url = navAction.request.url,
               !url.absoluteString.isEmpty,
               url.absoluteString != "about:blank" {
                print("🔗 [POPUP] Загружаем URL в popup: \(url.absoluteString)")
                popupWebView.load(navAction.request)
            }
            
            return popupWebView
        }
        
        // Закрытие временного WebView
        public func webViewDidClose(_ webView: WKWebView) {
            print("❌ [CLOSE] ========================================")
            print("❌ [CLOSE] JavaScript вызвал window.close()")
            print("❌ [CLOSE] URL перед закрытием: \(webView.url?.absoluteString ?? "nil")")
            print("❌ [CLOSE] Это popup WebView?: \(popupControllers[webView] != nil)")
            
            // Проверяем, это popup WebView?
            if let popupController = popupControllers[webView] {
                print("🔧 [CLOSE] Закрываем popup контроллер")
                popupController.closePopup()
            }
            
            // Legacy: старый механизм для временного WebView
            if webView == oauthWebView {
                oauthWebView = nil
                print("🗑️ [CLOSE] Временный WebView уничтожен (oauthWebView = nil)")
            }
            
            print("❌ [CLOSE] ========================================")
        }
        
        // MARK: -- Popup Management Functions
        
        /// Вызывается когда popup закрывается
        func popupDidClose(_ webView: WKWebView?) {
            guard let webView = webView else { return }
            
            print("🗑️ [POPUP CLOSE] Удаляем popup из словаря")
            popupControllers.removeValue(forKey: webView)
            print("📊 [POPUP CLOSE] Осталось popup'ов: \(popupControllers.count)")
        }
        
        // Обработка начала навигации
        public func webView(_ galaxyWebView: WKWebView, didStartProvisionalNavigation galaxyNavigation: WKNavigation!) {
            print("🚀 [NAV START] ========================================")
            print("🚀 [NAV START] Началась навигация")
            print("🚀 [NAV START] URL: \(galaxyWebView.url?.absoluteString ?? "nil")")
            print("🚀 [NAV START] Это временный WebView?: \(galaxyWebView == oauthWebView)")
            print("🚀 [NAV START] Это popup WebView?: \(popupControllers[galaxyWebView] != nil)")
            print("🚀 [NAV START] Это главный WebView?: \(galaxyWebView == galaxyWVView)")
            
            // Если это popup WebView - не перехватываем, пусть работает самостоятельно
            if popupControllers[galaxyWebView] != nil {
                print("🪟 [NAV START] Popup WebView навигирует самостоятельно")
                print("🚀 [NAV START] ========================================")
                return
            }
            
            // Legacy: Если это старый временный WebView - перехватываем URL
            if galaxyWebView == oauthWebView, let realUrl = galaxyWebView.url {
                let urlString = realUrl.absoluteString
                print("🔍 [NAV START] Проверяем URL временного WebView: \(urlString)")
                
                // Игнорируем пустые URL и about:blank
                if !urlString.isEmpty && 
                   urlString != "about:blank" &&
                   !urlString.hasPrefix("about:") {
                    print("✅ [NAV START] URL валидный! Переносим в основной WebView")
                    // Загружаем в основной WebView
                    if let mainWebView = galaxyWVView {
                        mainWebView.load(URLRequest(url: realUrl))
                        oauthWebView = nil
                        print("🔄 [NAV START] Временный WebView уничтожен (oauthWebView = nil)")
                    }
                    return
                } else {
                    print("⏭️ [NAV START] URL игнорируется (пустой или about:)")
                }
            }
            print("🚀 [NAV START] ========================================")
        }
        
        // Обработка завершения загрузки
        public func webView(_ galaxyWebView: WKWebView, didFinish galaxyNavigation: WKNavigation!) {
            print("✅ [FINISH] ========================================")
            print("✅ [FINISH] Загрузка завершена")
            print("✅ [FINISH] URL: \(galaxyWebView.url?.absoluteString ?? "nil")")
            print("✅ [FINISH] Это временный WebView?: \(galaxyWebView == oauthWebView)")
            print("✅ [FINISH] Это popup WebView?: \(popupControllers[galaxyWebView] != nil)")
            print("✅ [FINISH] Это главный WebView?: \(galaxyWebView == galaxyWVView)")
            print("✅ [FINISH] ========================================")
            galaxyRefreshControl?.endRefreshing()
        }
        
        // Обработка ошибок загрузки
        public func webView(_ galaxyWebView: WKWebView, didFail galaxyNavigation: WKNavigation!, withError galaxyError: Error) {
            print("❌ [ERROR] ========================================")
            print("❌ [ERROR] Ошибка при загрузке")
            print("❌ [ERROR] URL: \(galaxyWebView.url?.absoluteString ?? "nil")")
            print("❌ [ERROR] Error: \(galaxyError.localizedDescription)")
            print("❌ [ERROR] Это временный WebView?: \(galaxyWebView == oauthWebView)")
            print("❌ [ERROR] Это popup WebView?: \(popupControllers[galaxyWebView] != nil)")
            print("❌ [ERROR] ========================================")
            galaxyRefreshControl?.endRefreshing()
        }
        
        // Обработка ошибок загрузки (провизорная навигация)
        public func webView(_ galaxyWebView: WKWebView, didFailProvisionalNavigation galaxyNavigation: WKNavigation!, withError galaxyError: Error) {
            print("⚠️ [ERROR PROV] ========================================")
            print("⚠️ [ERROR PROV] Ошибка при провизорной навигации")
            print("⚠️ [ERROR PROV] URL: \(galaxyWebView.url?.absoluteString ?? "nil")")
            print("⚠️ [ERROR PROV] Error: \(galaxyError.localizedDescription)")
            print("⚠️ [ERROR PROV] Это временный WebView?: \(galaxyWebView == oauthWebView)")
            print("⚠️ [ERROR PROV] Это popup WebView?: \(popupControllers[galaxyWebView] != nil)")
            print("⚠️ [ERROR PROV] ========================================")
        }
    }
}

/// SwiftUI обертка для ContentDisplayView с отступами от safe area
public struct SafeContentDisplayView: View {
    let urlString: String
    let allowsGestures: Bool
    let enableRefresh: Bool
    
    public init(urlString: String, allowsGestures: Bool = true, enableRefresh: Bool = true) {
        self.urlString = urlString
        self.allowsGestures = allowsGestures
        self.enableRefresh = enableRefresh
    }
    
    public var body: some View {
        ZStack {
            // Черный фон
            Color.black
                .ignoresSafeArea()
            
            // WebView с отступами от safe area
            ContentDisplayView(
                urlString: urlString,
                allowsGestures: allowsGestures,
                enableRefresh: enableRefresh
            )
            .ignoresSafeArea(.keyboard)
            .onAppear {
               
                
                // Запрос оценки при третьем запуске
                let launchCount = UserDefaults.standard.integer(forKey: "animationGalaxyLaunchCount")
                if launchCount == 2 {
                    if let scene = UIApplication.shared
                        .connectedScenes
                        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                        SKStoreReviewController.requestReview(in: scene)
                    }
                }
            }
        }
    }
}
