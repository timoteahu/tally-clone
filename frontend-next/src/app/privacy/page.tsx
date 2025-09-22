import Link from "next/link";

export default function PrivacyPage() {
  return (
    <div className="min-h-screen bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-4xl mx-auto">
        <div className="bg-white shadow-lg rounded-lg overflow-hidden">
          {/* Header */}
          <div className="bg-gradient-to-r from-blue-600 to-purple-600 px-6 py-8">
            <h1 className="text-3xl font-bold text-white text-center">
              Privacy Policy
            </h1>
            <p className="text-blue-100 text-center mt-2">
              Last updated: {new Date().toLocaleDateString()}
            </p>
          </div>

          {/* Content */}
          <div className="px-6 py-8 space-y-8">
            {/* Introduction */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Introduction
              </h2>
              <p className="text-gray-700 leading-relaxed">
                Tally ("we," "our," or "us") is committed to protecting your
                privacy. This Privacy Policy explains how we collect, use,
                disclose, and safeguard your information when you use our mobile
                application and related services (collectively, the "Service").
              </p>
            </section>

            {/* Information We Collect */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Information We Collect
              </h2>

              <h3 className="text-xl font-medium text-gray-800 mb-3">
                Personal Information
              </h3>
              <ul className="list-disc list-inside text-gray-700 space-y-2 mb-6">
                <li>Name and contact information (phone number, email)</li>
                <li>Profile information and preferences</li>
                <li>
                  Payment and billing information (processed securely through
                  Stripe)
                </li>
                <li>Authentication credentials</li>
              </ul>

              <h3 className="text-xl font-medium text-gray-800 mb-3">
                Health and Activity Data
              </h3>
              <div className="bg-blue-50 border-l-4 border-blue-400 p-4 mb-4">
                <p className="text-blue-800 font-medium mb-2">
                  Apple HealthKit Integration
                </p>
                <p className="text-blue-700 text-sm">
                  Our app integrates with Apple HealthKit to help you track and
                  verify your health-related habits. We only access the specific
                  health data types you explicitly authorize.
                </p>
              </div>
              <ul className="list-disc list-inside text-gray-700 space-y-2 mb-6">
                <li>
                  Workout data (gym sessions, yoga, cycling, outdoor activities)
                </li>
                <li>Step count and activity metrics</li>
                <li>Sleep data (when relevant to habit tracking)</li>
                <li>Nutrition and dietary information (when applicable)</li>
                <li>Other health metrics you choose to share</li>
              </ul>

              <h3 className="text-xl font-medium text-gray-800 mb-3">
                Usage and Analytics Data
              </h3>
              <ul className="list-disc list-inside text-gray-700 space-y-2 mb-6">
                <li>App usage patterns and interactions</li>
                <li>Habit creation, completion, and verification data</li>
                <li>Social interactions (friends, accountability partners)</li>
                <li>Device information and app performance data</li>
              </ul>
            </section>

            {/* How We Use Your Information */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                How We Use Your Information
              </h2>
              <ul className="list-disc list-inside text-gray-700 space-y-2">
                <li>Provide and maintain the Service</li>
                <li>Process payments and manage your account</li>
                <li>Track and verify your habit completion</li>
                <li>Enable social features and accountability partnerships</li>
                <li>Send notifications and updates about your habits</li>
                <li>Improve our services and develop new features</li>
                <li>Ensure security and prevent fraud</li>
                <li>Comply with legal obligations</li>
              </ul>
            </section>

            {/* HealthKit Specific Information */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Apple HealthKit Integration
              </h2>
              <div className="bg-green-50 border border-green-200 rounded-lg p-6">
                <h3 className="text-lg font-semibold text-green-800 mb-3">
                  Your Health Data Privacy
                </h3>
                <ul className="space-y-3 text-green-700">
                  <li className="flex items-start">
                    <span className="text-green-600 mr-2">✓</span>
                    <span>
                      We only access health data you explicitly authorize
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-green-600 mr-2">✓</span>
                    <span>
                      Health data is stored locally on your device and in your
                      iCloud
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-green-600 mr-2">✓</span>
                    <span>
                      We do not sell, rent, or share your health data with third
                      parties
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-green-600 mr-2">✓</span>
                    <span>
                      You can revoke HealthKit permissions at any time in your
                      device settings
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-green-600 mr-2">✓</span>
                    <span>
                      Health data is only used to verify habit completion and
                      provide insights
                    </span>
                  </li>
                </ul>
              </div>

              <div className="mt-6">
                <h3 className="text-lg font-medium text-gray-800 mb-3">
                  Health Data Types We Access
                </h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="bg-gray-50 p-4 rounded-lg">
                    <h4 className="font-medium text-gray-800 mb-2">
                      Workout Data
                    </h4>
                    <p className="text-sm text-gray-600">
                      Gym sessions, yoga, cycling, outdoor activities
                    </p>
                  </div>
                  <div className="bg-gray-50 p-4 rounded-lg">
                    <h4 className="font-medium text-gray-800 mb-2">
                      Activity Metrics
                    </h4>
                    <p className="text-sm text-gray-600">
                      Step count, active energy, exercise minutes
                    </p>
                  </div>
                  <div className="bg-gray-50 p-4 rounded-lg">
                    <h4 className="font-medium text-gray-800 mb-2">
                      Sleep Data
                    </h4>
                    <p className="text-sm text-gray-600">
                      Sleep duration and quality (when relevant)
                    </p>
                  </div>
                  <div className="bg-gray-50 p-4 rounded-lg">
                    <h4 className="font-medium text-gray-800 mb-2">
                      Nutrition Data
                    </h4>
                    <p className="text-sm text-gray-600">
                      Dietary information (when applicable)
                    </p>
                  </div>
                </div>
              </div>
            </section>

            {/* Data Sharing and Third Parties */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Data Sharing and Third Parties
              </h2>
              <p className="text-gray-700 mb-4">
                We do not sell, rent, or trade your personal information to
                third parties. We may share your information in the following
                limited circumstances:
              </p>
              <ul className="list-disc list-inside text-gray-700 space-y-2">
                <li>
                  <strong>Service Providers:</strong> We use trusted third-party
                  services for payment processing (Stripe), cloud storage, and
                  analytics
                </li>
                <li>
                  <strong>Legal Requirements:</strong> When required by law or
                  to protect our rights and safety
                </li>
                <li>
                  <strong>Business Transfers:</strong> In connection with a
                  merger, acquisition, or sale of assets
                </li>
                <li>
                  <strong>With Your Consent:</strong> When you explicitly
                  authorize us to share your information
                </li>
              </ul>
            </section>

            {/* Data Security */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Data Security
              </h2>
              <p className="text-gray-700 mb-4">
                We implement appropriate technical and organizational measures
                to protect your personal information:
              </p>
              <ul className="list-disc list-inside text-gray-700 space-y-2">
                <li>End-to-end encryption for sensitive data transmission</li>
                <li>Secure cloud storage with industry-standard security</li>
                <li>Regular security audits and updates</li>
                <li>Access controls and authentication measures</li>
                <li>Compliance with data protection regulations</li>
              </ul>
            </section>

            {/* Your Rights */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Your Rights and Choices
              </h2>
              <ul className="list-disc list-inside text-gray-700 space-y-2">
                <li>
                  <strong>Access:</strong> Request a copy of your personal
                  information
                </li>
                <li>
                  <strong>Correction:</strong> Update or correct your
                  information
                </li>
                <li>
                  <strong>Deletion:</strong> Request deletion of your account
                  and data
                </li>
                <li>
                  <strong>Portability:</strong> Export your data in a
                  machine-readable format
                </li>
                <li>
                  <strong>Opt-out:</strong> Unsubscribe from marketing
                  communications
                </li>
                <li>
                  <strong>HealthKit Permissions:</strong> Manage HealthKit
                  access in your device settings
                </li>
              </ul>
            </section>

            {/* Children's Privacy */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Children's Privacy
              </h2>
              <p className="text-gray-700">
                Our Service is not intended for children under 13 years of age.
                We do not knowingly collect personal information from children
                under 13. If you are a parent or guardian and believe your child
                has provided us with personal information, please contact us
                immediately.
              </p>
            </section>

            {/* International Users */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                International Users
              </h2>
              <p className="text-gray-700">
                If you are accessing our Service from outside the United States,
                please be aware that your information may be transferred to,
                stored, and processed in the United States where our servers are
                located. By using our Service, you consent to the transfer of
                your information to the United States.
              </p>
            </section>

            {/* Changes to Privacy Policy */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Changes to This Privacy Policy
              </h2>
              <p className="text-gray-700">
                We may update this Privacy Policy from time to time. We will
                notify you of any changes by posting the new Privacy Policy on
                this page and updating the "Last updated" date. We encourage you
                to review this Privacy Policy periodically for any changes.
              </p>
            </section>

            {/* Contact Information */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Contact Us
              </h2>
              <p className="text-gray-700 mb-4">
                If you have any questions about this Privacy Policy or our data
                practices, please contact us:
              </p>
              <div className="bg-gray-50 p-4 rounded-lg">
                <p className="text-gray-700">
                  <strong>Email:</strong> privacy@jointally.app
                  <br />
                  <strong>Address:</strong> [Your Business Address]
                  <br />
                  <strong>Website:</strong> jointally.app
                </p>
              </div>
            </section>

            {/* Footer */}
            <div className="border-t pt-6 mt-8">
              <p className="text-sm text-gray-500 text-center">
                By using Tally, you agree to the terms outlined in this Privacy
                Policy.
              </p>
              <div className="flex justify-center mt-4 space-x-4">
                <Link
                  href="/"
                  className="text-blue-600 hover:text-blue-800 text-sm"
                >
                  Back to Home
                </Link>
                <Link
                  href="/terms"
                  className="text-blue-600 hover:text-blue-800 text-sm"
                >
                  Terms of Service
                </Link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
