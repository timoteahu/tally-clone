import SwiftUI

/// A container that provides lazy initialization for managers
/// This reduces app startup time by only initializing managers when they're first accessed
@MainActor
final class LazyManagerContainer: ObservableObject {
    static let shared = LazyManagerContainer()
    
    // Core managers that are always needed
    @Published private(set) var authManager: AuthenticationManager
    @Published private(set) var loadingManager: LoadingStateManager
    @Published private(set) var dataCacheManager: DataCacheManager
    
    // Lazy-loaded managers
    private var _habitManager: HabitManager?
    private var _paymentManager: PaymentManager?
    private var _feedManager: FeedManager?
    private var _friendsManager: FriendsManager?
    private var _contactManager: ContactManager?
    private var _customHabitManager: CustomHabitManager?
    private var _recipientAnalyticsManager: RecipientAnalyticsManager?
    private var _notificationManager: NotificationManager?
    private var _backgroundUpdateManager: BackgroundUpdateManager?
    private var _paymentStatsManager: PaymentStatsManager?
    private var _owedAmountManager: OwedAmountManager?
    private var _storeManager: StoreManager?
    
    private init() {
        // Initialize only critical managers needed at startup
        self.authManager = AuthenticationManager.shared
        self.loadingManager = LoadingStateManager.shared
        self.dataCacheManager = DataCacheManager.shared
    }
    
    // MARK: - Lazy Accessors
    
    var habitManager: HabitManager {
        if _habitManager == nil {
            _habitManager = HabitManager.shared
        }
        return _habitManager!
    }
    
    var paymentManager: PaymentManager {
        if _paymentManager == nil {
            _paymentManager = PaymentManager.shared
        }
        return _paymentManager!
    }
    
    var feedManager: FeedManager {
        if _feedManager == nil {
            _feedManager = FeedManager.shared
        }
        return _feedManager!
    }
    
    var friendsManager: FriendsManager {
        if _friendsManager == nil {
            _friendsManager = FriendsManager.shared
        }
        return _friendsManager!
    }
    
    var contactManager: ContactManager {
        if _contactManager == nil {
            _contactManager = ContactManager.shared
        }
        return _contactManager!
    }
    
    var customHabitManager: CustomHabitManager {
        if _customHabitManager == nil {
            _customHabitManager = CustomHabitManager.shared
        }
        return _customHabitManager!
    }
    
    var recipientAnalyticsManager: RecipientAnalyticsManager {
        if _recipientAnalyticsManager == nil {
            _recipientAnalyticsManager = RecipientAnalyticsManager.shared
        }
        return _recipientAnalyticsManager!
    }
    
    var notificationManager: NotificationManager {
        if _notificationManager == nil {
            _notificationManager = NotificationManager.shared
        }
        return _notificationManager!
    }
    
    var backgroundUpdateManager: BackgroundUpdateManager {
        if _backgroundUpdateManager == nil {
            _backgroundUpdateManager = BackgroundUpdateManager.shared
        }
        return _backgroundUpdateManager!
    }
    
    var paymentStatsManager: PaymentStatsManager {
        if _paymentStatsManager == nil {
            _paymentStatsManager = PaymentStatsManager.shared
        }
        return _paymentStatsManager!
    }
    
    var owedAmountManager: OwedAmountManager {
        if _owedAmountManager == nil {
            _owedAmountManager = OwedAmountManager()
        }
        return _owedAmountManager!
    }
    
    var storeManager: StoreManager {
        if _storeManager == nil {
            _storeManager = StoreManager()
        }
        return _storeManager!
    }
    
    // MARK: - Preloading Support
    
    /// Preload specific managers that will be needed soon
    func preloadManagers(for tab: Int) {
        switch tab {
        case 0: // Home tab
            _ = habitManager
            _ = paymentManager
        case 1: // Feed tab
            _ = feedManager
            _ = friendsManager
        case 2: // Profile tab
            _ = paymentStatsManager
            _ = recipientAnalyticsManager
        default:
            break
        }
    }
    
    /// Force initialization of all managers (for specific use cases like app restore)
    func initializeAllManagers() {
        _ = habitManager
        _ = paymentManager
        _ = feedManager
        _ = friendsManager
        _ = contactManager
        _ = customHabitManager
        _ = recipientAnalyticsManager
        _ = notificationManager
        _ = backgroundUpdateManager
        _ = paymentStatsManager
        _ = owedAmountManager
        _ = storeManager
    }
}

// MARK: - Environment Key
private struct LazyManagerContainerKey: EnvironmentKey {
    static var defaultValue: LazyManagerContainer {
        // Since EnvironmentValues are always accessed from Views (MainActor context),
        // we can safely assume we're on MainActor here
        MainActor.assumeIsolated {
            LazyManagerContainer.shared
        }
    }
}

extension EnvironmentValues {
    var lazyManagers: LazyManagerContainer {
        get { self[LazyManagerContainerKey.self] }
        set { self[LazyManagerContainerKey.self] = newValue }
    }
}