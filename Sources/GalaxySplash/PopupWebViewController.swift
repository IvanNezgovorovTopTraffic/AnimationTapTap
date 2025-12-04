import UIKit
import WebKit

// MARK: - Popup WebView Controller

/// Контроллер для отображения popup WebView модально
final class PopupWebViewController: UIViewController {
    
    // MARK: -- Private Properties
    
    private var webView: WKWebView
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("✕", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 28, weight: .light)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private weak var coordinator: ContentDisplayView.Coordinator?
    
    // MARK: -- Init
    
    init(webView: WKWebView, coordinator: ContentDisplayView.Coordinator) {
        self.webView = webView
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
        
        // Модальное представление
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: -- Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        print("🪟 [POPUP VIEW] PopupWebViewController загружен")
    }
    
    // MARK: -- Private Functions
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // Добавляем WebView
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        
        // Добавляем кнопку закрытия
        view.addSubview(closeButton)
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        
        // Constraints
        NSLayoutConstraint.activate([
            // WebView на весь экран
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Кнопка закрытия в правом верхнем углу
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    @objc private func closeButtonTapped() {
        print("❌ [POPUP VIEW] Пользователь закрыл popup")
        
        // Вызываем JavaScript window.close() для корректного закрытия
        webView.evaluateJavaScript("window.close();") { _, error in
            if let error = error {
                print("⚠️ [POPUP VIEW] Ошибка при вызове window.close(): \(error)")
            }
        }
        
        // Закрываем модальное окно
        dismiss(animated: true) { [weak self] in
            print("✅ [POPUP VIEW] Popup закрыт")
            // Уведомляем координатор
            self?.coordinator?.popupDidClose(self?.webView)
        }
    }
    
    // MARK: -- Public Functions
    
    /// Программное закрытие popup (когда JavaScript вызывает window.close())
    func closePopup() {
        print("🔧 [POPUP VIEW] Программное закрытие popup")
        dismiss(animated: true) { [weak self] in
            print("✅ [POPUP VIEW] Popup закрыт программно")
            self?.coordinator?.popupDidClose(self?.webView)
        }
    }
}

