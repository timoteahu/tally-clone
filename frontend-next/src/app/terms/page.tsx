import Link from "next/link";

export default function TermsPage() {
  return (
    <div className="min-h-screen bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-4xl mx-auto">
        <div className="bg-white shadow-lg rounded-lg overflow-hidden">
          {/* Header */}
          <div className="bg-gradient-to-r from-purple-600 to-blue-600 px-6 py-8">
            <h1 className="text-3xl font-bold text-white text-center">
              Terms of Service
            </h1>
            <p className="text-purple-100 text-center mt-2">
              Last updated: {new Date().toLocaleDateString()}
            </p>
          </div>

          {/* Content */}
          <div className="px-6 py-8 space-y-8">
            {/* Introduction */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Agreement to Terms
              </h2>
              <p className="text-gray-700 leading-relaxed">
                By accessing and using Tally ("the Service"), you accept and
                agree to be bound by the terms and provision of this agreement.
                If you do not agree to abide by the above, please do not use
                this service.
              </p>
            </section>

            {/* Description of Service */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Description of Service
              </h2>
              <p className="text-gray-700 mb-4">
                Tally is a habit-building application that helps users create,
                track, and maintain positive habits through:
              </p>
              <ul className="list-disc list-inside text-gray-700 space-y-2">
                <li>Habit creation and goal setting</li>
                <li>Progress tracking and verification</li>
                <li>Social accountability with friends</li>
                <li>Financial incentives and penalties</li>
                <li>Health data integration for verification</li>
                <li>Payment processing for penalties and rewards</li>
              </ul>
            </section>

            {/* User Accounts */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                User Accounts and Registration
              </h2>
              <p className="text-gray-700 mb-4">
                To use certain features of the Service, you must register for an
                account. You agree to:
              </p>
              <ul className="list-disc list-inside text-gray-700 space-y-2">
                <li>
                  Provide accurate, current, and complete information during
                  registration
                </li>
                <li>Maintain and update your account information</li>
                <li>Keep your account credentials secure and confidential</li>
                <li>
                  Accept responsibility for all activities under your account
                </li>
                <li>
                  Notify us immediately of any unauthorized use of your account
                </li>
              </ul>
            </section>

            {/* HealthKit Integration */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Apple HealthKit Integration
              </h2>
              <div className="bg-blue-50 border border-blue-200 rounded-lg p-6 mb-4">
                <h3 className="text-lg font-semibold text-blue-800 mb-3">
                  Health Data Usage
                </h3>
                <p className="text-blue-700 mb-4">
                  Our app integrates with Apple HealthKit to provide enhanced
                  habit tracking and verification capabilities.
                </p>
                <ul className="space-y-2 text-blue-700">
                  <li className="flex items-start">
                    <span className="text-blue-600 mr-2">•</span>
                    <span>
                      You must explicitly authorize access to specific health
                      data types
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-blue-600 mr-2">•</span>
                    <span>
                      Health data is used solely for habit verification and
                      progress tracking
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-blue-600 mr-2">•</span>
                    <span>
                      You can revoke HealthKit permissions at any time
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-blue-600 mr-2">•</span>
                    <span>
                      We comply with Apple's HealthKit guidelines and privacy
                      requirements
                    </span>
                  </li>
                </ul>
              </div>
            </section>

            {/* Payment Terms */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Payment Terms and Penalties
              </h2>
              <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-6 mb-4">
                <h3 className="text-lg font-semibold text-yellow-800 mb-3">
                  Important Payment Information
                </h3>
                <ul className="space-y-2 text-yellow-700">
                  <li className="flex items-start">
                    <span className="text-yellow-600 mr-2">⚠</span>
                    <span>
                      Penalties are charged when you fail to complete your
                      habits
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-yellow-600 mr-2">⚠</span>
                    <span>
                      All payments are processed securely through Stripe
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-yellow-600 mr-2">⚠</span>
                    <span>
                      You must maintain a valid payment method on file
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-yellow-600 mr-2">⚠</span>
                    <span>
                      Failed payments may result in account suspension
                    </span>
                  </li>
                </ul>
              </div>

              <h3 className="text-xl font-medium text-gray-800 mb-3">
                Payment Processing
              </h3>
              <ul className="list-disc list-inside text-gray-700 space-y-2">
                <li>
                  All payments are processed by Stripe, a third-party payment
                  processor
                </li>
                <li>
                  You authorize us to charge your payment method for penalties
                </li>
                <li>Payment amounts are determined by your habit settings</li>
                <li>Refunds are subject to our refund policy</li>
                <li>You are responsible for maintaining sufficient funds</li>
              </ul>
            </section>

            {/* Acceptable Use */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Acceptable Use Policy
              </h2>
              <p className="text-gray-700 mb-4">
                You agree not to use the Service to:
              </p>
              <ul className="list-disc list-inside text-gray-700 space-y-2">
                <li>Violate any applicable laws or regulations</li>
                <li>Infringe on the rights of others</li>
                <li>
                  Upload or transmit harmful, offensive, or inappropriate
                  content
                </li>
                <li>Attempt to gain unauthorized access to our systems</li>
                <li>Interfere with the proper functioning of the Service</li>
                <li>
                  Use the Service for commercial purposes without authorization
                </li>
                <li>Create fake accounts or manipulate the penalty system</li>
              </ul>
            </section>

            {/* Intellectual Property */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Intellectual Property Rights
              </h2>
              <p className="text-gray-700 mb-4">
                The Service and its original content, features, and
                functionality are owned by Tally and are protected by
                international copyright, trademark, patent, trade secret, and
                other intellectual property laws.
              </p>
              <p className="text-gray-700">
                You retain ownership of content you create, but grant us a
                license to use it for providing the Service.
              </p>
            </section>

            {/* Privacy */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Privacy and Data Protection
              </h2>
              <p className="text-gray-700 mb-4">
                Your privacy is important to us. Please review our Privacy
                Policy, which also governs your use of the Service, to
                understand our practices.
              </p>
              <div className="bg-gray-50 p-4 rounded-lg">
                <p className="text-gray-700">
                  <strong>Health Data:</strong> We handle your health data in
                  accordance with applicable privacy laws and Apple's HealthKit
                  guidelines. Your health data is used only for the purposes you
                  authorize and is protected by appropriate security measures.
                </p>
              </div>
            </section>

            {/* Disclaimers */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Disclaimers and Limitations
              </h2>
              <div className="bg-red-50 border border-red-200 rounded-lg p-6 mb-4">
                <h3 className="text-lg font-semibold text-red-800 mb-3">
                  Important Disclaimers
                </h3>
                <ul className="space-y-2 text-red-700">
                  <li className="flex items-start">
                    <span className="text-red-600 mr-2">•</span>
                    <span>
                      The Service is provided "as is" without warranties of any
                      kind
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-red-600 mr-2">•</span>
                    <span>
                      We are not responsible for the success or failure of your
                      habits
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-red-600 mr-2">•</span>
                    <span>
                      Health data integration is not a substitute for
                      professional medical advice
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-red-600 mr-2">•</span>
                    <span>
                      We do not guarantee uninterrupted or error-free service
                    </span>
                  </li>
                </ul>
              </div>
            </section>

            {/* Limitation of Liability */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Limitation of Liability
              </h2>
              <p className="text-gray-700">
                In no event shall Tally, nor its directors, employees, partners,
                agents, suppliers, or affiliates, be liable for any indirect,
                incidental, special, consequential, or punitive damages,
                including without limitation, loss of profits, data, use,
                goodwill, or other intangible losses, resulting from your use of
                the Service.
              </p>
            </section>

            {/* Termination */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Termination
              </h2>
              <p className="text-gray-700 mb-4">
                We may terminate or suspend your account and bar access to the
                Service immediately, without prior notice or liability, under
                our sole discretion, for any reason whatsoever, including
                without limitation if you breach the Terms.
              </p>
              <p className="text-gray-700">
                Upon termination, your right to use the Service will cease
                immediately. If you wish to terminate your account, you may
                simply discontinue using the Service or contact us to delete
                your account.
              </p>
            </section>

            {/* Governing Law */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Governing Law
              </h2>
              <p className="text-gray-700">
                These Terms shall be interpreted and governed by the laws of the
                United States, without regard to its conflict of law provisions.
                Our failure to enforce any right or provision of these Terms
                will not be considered a waiver of those rights.
              </p>
            </section>

            {/* Changes to Terms */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Changes to Terms
              </h2>
              <p className="text-gray-700">
                We reserve the right, at our sole discretion, to modify or
                replace these Terms at any time. If a revision is material, we
                will provide at least 30 days notice prior to any new terms
                taking effect. What constitutes a material change will be
                determined at our sole discretion.
              </p>
            </section>

            {/* Contact Information */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Contact Information
              </h2>
              <p className="text-gray-700 mb-4">
                If you have any questions about these Terms of Service, please
                contact us:
              </p>
              <div className="bg-gray-50 p-4 rounded-lg">
                <p className="text-gray-700">
                  <strong>Email:</strong> legal@jointally.app
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
                By using Tally, you acknowledge that you have read, understood,
                and agree to be bound by these Terms of Service.
              </p>
              <div className="flex justify-center mt-4 space-x-4">
                <Link
                  href="/"
                  className="text-blue-600 hover:text-blue-800 text-sm"
                >
                  Back to Home
                </Link>
                <Link
                  href="/privacy"
                  className="text-blue-600 hover:text-blue-800 text-sm"
                >
                  Privacy Policy
                </Link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
