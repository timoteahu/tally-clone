/// Previously this function cleared today's verification dictionaries before a background
/// sync, which caused the UI graph to flash to 0 while fresh data was still loading.
/// We now retain the existing data until new results arrive to avoid that flicker.
@MainActor
func resetTodaysVerificationData() {
    // Intentionally left blank – we keep existing verification state while syncing.
    // The incoming /sync or /habit-verification/get-week response will update the
    // dictionaries as soon as it finishes.
} 