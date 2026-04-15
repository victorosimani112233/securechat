# SecureChatContacts - iOS Contacts Module

iOS implementation of privacy-preserving contact management and user discovery for SecureChat.

## Overview

This module provides complete contact management functionality for iOS, equivalent to the Android contacts implementation. It uses the iOS Contacts framework for device contact access and implements privacy-preserving contact discovery via phone number hashing.

## Key Features

### Privacy-First Contact Discovery
- **No plaintext phone numbers sent to server** - Only SHA-256 hashes are transmitted
- **Client-side matching** - Contact data never leaves the device
- **Graceful degradation** - App works without contact permissions (manual number entry)

### iOS Platform Integration
- **Contacts Framework** - Native iOS contact access using CNContactStore
- **ContactsUI Framework** - Native contact picker interface
- **Permission Management** - Proper iOS contact permission handling
- **Background Sync** - Automatic contact discovery on contact changes

### Cross-Platform Compatibility
- **Same API surface** - Consistent with Android implementation
- **Shared hashing algorithm** - SHA-256 ensures cross-platform contact discovery
- **E.164 normalization** - Consistent phone number formatting

## Architecture

```
ContactsService (Main API)
├── ContactsManager (Device contact access)
├── ContactPermissionManager (iOS permissions)
├── ContactDiscoveryService (Server-side matching)
├── PhoneNumberHasher (Privacy-preserving hashing)
├── PhoneNumberNormalizer (E.164 formatting)
└── ContactDiscoveryNetworkService (Network layer)
```

## Core Components

### ContactsService
Main service providing unified contact management API:
```swift
let contactsService = ContactsService(...)

// Request permissions and sync contacts
await contactsService.requestContactPermission()
await contactsService.syncContacts()

// Access registered contacts
let registeredContacts = contactsService.getRegisteredContacts()
let contact = contactsService.findRegisteredContact(by: phoneNumber)
```

### ContactsManager
Device contact access using iOS Contacts framework:
```swift
let contactsManager = ContactsManager()

// Read all device contacts
let deviceContacts = try await contactsManager.getAllContacts()

// Search contacts
let searchResults = try await contactsManager.searchContacts(query: "John")
```

### ContactPermissionManager
iOS-specific contact permission management:
```swift
let permissionManager = ContactPermissionManager()

// Check current permission status
let hasPermission = permissionManager.hasPermission

// Request permission (iOS 13+ async/await)
let granted = await permissionManager.requestPermission()

// Handle permission denial
if !granted {
    permissionManager.openSettings()
}
```

### ContactDiscoveryService
Privacy-preserving user discovery:
```swift
let discoveryService = ContactDiscoveryService(...)

// Discover registered users (hashes only sent to server)
let result = try await discoveryService.discoverRegisteredUsers()
print("Found \(result.registeredCount) registered contacts")

// Check specific numbers
let registeredUsers = try await discoveryService.checkSpecificNumbers(["+905551234567"])
```

### PhoneNumberHasher
SHA-256 hashing for privacy:
```swift
let hasher = PhoneNumberHasher()

// Hash phone number (64-character hex string)
let hash = hasher.hashPhoneNumber("+905551234567")

// Batch hashing
let hashes = hasher.createHashes(from: phoneNumbers)
```

### PhoneNumberNormalizer
E.164 phone number normalization:
```swift
let normalizer = PhoneNumberNormalizer()

// Various input formats -> E.164
let e164 = normalizer.normalizeToE164("0555 123 45 67") // "+905551234567"
let userId = normalizer.normalizeToUserId("+90 555 123 45 67") // "905551234567"
let display = normalizer.formatForDisplay("905551234567") // "+90 555 123 45 67"
```

## Privacy & Security

### Privacy Guarantees
1. **No plaintext phone numbers sent to server** - Only SHA-256 hashes transmitted
2. **Contact data stays on device** - Server never sees contact names or raw numbers
3. **Minimal data collection** - Only necessary for contact discovery
4. **User consent required** - Explicit permission before accessing contacts

### Security Measures
1. **SHA-256 hashing** - Cryptographically secure one-way function
2. **E.164 normalization** - Consistent formatting prevents hash variations
3. **Input validation** - All phone numbers validated before processing
4. **Error handling** - Graceful failure modes, no data leakage

### Compliance
- **GDPR compliant** - No personal data sent to server without hashing
- **iOS privacy guidelines** - Proper permission requests and user notification
- **Minimal data principle** - Only hash necessary contact data

## Usage Examples

### Basic Setup
```swift
import SecureChatContacts
import SecureChatStorage

// Setup dependencies
let contactDAO = ContactDAO()
let networkService = ContactDiscoveryNetworkServiceFactory.create(
    baseURL: URL(string: "https://api.securechat.com")!
)

// Create main service
let contactsService = ContactsService(
    contactsManager: ContactsManager(),
    permissionManager: ContactPermissionManager(),
    discoveryService: ContactDiscoveryService(
        contactsManager: ContactsManager(),
        networkService: networkService
    ),
    contactDAO: contactDAO
)
```

### Permission Flow
```swift
// Check permission status
switch contactsService.permissionStatus {
case .notDetermined:
    let granted = await contactsService.requestContactPermission()
    if granted {
        await contactsService.syncContacts()
    }
case .denied:
    contactsService.openContactSettings()
case .authorized:
    await contactsService.syncContacts()
}
```

### Contact Discovery
```swift
// Sync with server (privacy-preserving)
await contactsService.syncContacts()

// Access discovered contacts
let registeredContacts = contactsService.getRegisteredContacts()

// Search registered contacts
let searchResults = contactsService.searchRegisteredContacts(query: "John")

// Check if specific number is registered
let isRegistered = contactsService.isPhoneNumberRegistered("+905551234567")
```

### Manual Contact Addition
```swift
// Add contact by phone number
let contact = try await contactsService.addManualContact(
    phoneNumber: "+90 555 123 45 67",
    displayName: "John Doe"
)
```

### Reactive Updates
```swift
// Observe contact sync status
contactsService.$syncStatus
    .sink { status in
        switch status {
        case .idle:
            // Not syncing
        case .syncing:
            // Show progress
        case .completed(let result):
            // Update UI with result.discoveredContacts
        case .failed(let error):
            // Handle error
        }
    }
    .store(in: &cancellables)

// Observe registered contacts
contactsService.$registeredContacts
    .sink { contacts in
        // Update contact list UI
    }
    .store(in: &cancellables)
```

## Testing

### Unit Tests
Comprehensive unit tests covering:
- Phone number normalization (various formats)
- Hash generation and validation
- Permission state management
- Contact discovery logic
- Error handling scenarios

### Mock Services
Mock implementations provided for testing:
```swift
let mockNetworkService = MockContactDiscoveryNetworkService()
mockNetworkService.setMockRegisteredUsers([
    ServerUser(userId: "user1", phoneHash: "hash1"),
    ServerUser(userId: "user2", phoneHash: "hash2")
])

let discoveryService = ContactDiscoveryService(
    contactsManager: contactsManager,
    networkService: mockNetworkService
)
```

### Integration Tests
Integration tests with actual iOS Contacts framework using test data.

## Performance

### Optimization Features
- **Batch processing** - Efficient bulk contact operations
- **Deduplication** - Removes duplicate phone numbers
- **Lazy loading** - Contacts loaded on demand
- **Background sync** - Non-blocking contact discovery
- **Pagination support** - Large contact lists handled efficiently

### Memory Management
- **Weak references** - Prevents retain cycles
- **Automatic cleanup** - Resources freed when not needed
- **Structured concurrency** - Modern Swift async/await patterns

## Error Handling

Comprehensive error handling with specific error types:
```swift
public enum ContactError: LocalizedError {
    case permissionDenied
    case contactsAccessFailed
    case normalizationFailed(phoneNumber: String)
    case discoveryFailed(underlying: Error)
    case hashingFailed
    case networkError(underlying: Error)
    case storageError(underlying: Error)
}
```

## Dependencies

### System Frameworks
- **Contacts.framework** - Device contact access
- **ContactsUI.framework** - Contact picker interface
- **CryptoKit.framework** - SHA-256 hashing
- **Combine.framework** - Reactive updates

### Internal Dependencies
- **SecureChatCommon** - Shared models and utilities
- **SecureChatStorage** - Contact persistence (ContactDAO)

### External Dependencies
None - Uses only iOS system frameworks and internal modules.

## Thread Safety

All public APIs are marked as `@unchecked Sendable` and are safe for concurrent access:
- **Main actor operations** - UI updates on main thread
- **Background processing** - Network and heavy operations on background threads
- **Actor isolation** - Proper async/await usage throughout

## Migration from Android

This iOS implementation maintains API compatibility with the Android version:

| Android Component | iOS Equivalent | Notes |
|------------------|----------------|--------|
| `ContactsProvider` | `ContactsManager` | Uses CNContactStore instead of ContentResolver |
| `ContactPermissionManager` | `ContactPermissionManager` | iOS-specific permission flow |
| `UserDiscoveryService` | `ContactDiscoveryService` | Same hashing algorithm |
| `PhoneNumberNormalizer` | `PhoneNumberNormalizer` | Identical normalization logic |
| `ContactsObserver` | Contact change publisher | Uses Combine instead of ContentObserver |

## Future Enhancements

Planned improvements:
- **Contact groups** - Support for contact groups/labels
- **Contact photos** - Avatar synchronization
- **Incremental sync** - Only sync changed contacts
- **Offline support** - Better offline contact discovery
- **Contact backup** - Secure contact backup/restore