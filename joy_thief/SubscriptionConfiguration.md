# Subscription Configuration Guide

## Apple App Store Connect Setup

To enable the subscription functionality in your app, you'll need to create the following subscription products in App Store Connect:

### Product IDs (must match exactly)
1. **Tally Insurance**: `com.joythief.tally.insurance`
2. **Tally Premium**: `com.joythief.tally.premium`

### Steps to Configure in App Store Connect:

1. **Log into App Store Connect**
   - Go to https://appstoreconnect.apple.com
   - Select your app

2. **Create Subscription Group**
   - Navigate to "In-App Purchases" section
   - Click the "+" button to create a new subscription group
   - Name it "Tally Subscriptions" or similar

3. **Add Tally Insurance Subscription**
   - Product ID: `com.joythief.tally.insurance`
   - Reference Name: `Tally Insurance`
   - Subscription Group: Select the group created above
   - Set pricing (e.g., $4.99/month)
   - Add localizations and descriptions

4. **Add Tally Premium Subscription**
   - Product ID: `com.joythief.tally.premium`
   - Reference Name: `Tally Premium`
   - Subscription Group: Same group as above
   - Set pricing (e.g., $9.99/month)
   - Add localizations and descriptions

5. **Configure Subscription Details**
   - Add subscription descriptions
   - Set up promotional images
   - Configure family sharing settings
   - Set up subscription review information

### Testing
- Use TestFlight or Sandbox environment for testing
- Create sandbox test users in App Store Connect
- Test both subscription tiers and cancellation flows

### Features by Tier

#### Tally Insurance ($X.XX/month)
- Habit backup & recovery
- Basic analytics
- Email support
- Data export (limited)

#### Tally Premium ($X.XX/month)
- Unlimited habit tracking
- Advanced analytics & insights
- Custom penalty recipients
- Priority customer support
- Export data capabilities

### Code Integration
The subscription product IDs are already configured in:
- `StoreManager.swift` - Handles the IAP logic
- `PremiumView.swift` - Displays the subscription options
- `ProfileView.swift` - Contains the upgrade button

### Notes
- Make sure to submit the subscriptions for review along with your app
- Test thoroughly in sandbox environment before going live
- Consider offering free trials or introductory pricing
- Ensure your app handles subscription status changes properly 