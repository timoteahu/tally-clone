import Link from "next/link";

export default function ContactPage() {
  return (
    <div className="min-h-screen bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-2xl mx-auto">
        <div className="bg-white shadow-lg rounded-lg overflow-hidden">
          {/* Header */}
          <div className="bg-gradient-to-r from-green-600 to-blue-600 px-6 py-8">
            <h1 className="text-3xl font-bold text-white text-center">
              Contact Us
            </h1>
            <p className="text-green-100 text-center mt-2">
              We'd love to hear from you
            </p>
          </div>

          {/* Content */}
          <div className="px-6 py-8 space-y-8">
            {/* Introduction */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Get in Touch
              </h2>
              <p className="text-gray-700 leading-relaxed">
                Have questions about Tally? Need help with your account? Want to
                share feedback? We're here to help!
              </p>
            </section>

            {/* Contact Methods */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Contact Information
              </h2>

              <div className="space-y-6">
                <div className="bg-blue-50 p-6 rounded-lg">
                  <h3 className="text-lg font-semibold text-blue-800 mb-2">
                    General Support
                  </h3>
                  <p className="text-blue-700 mb-3">
                    For general questions, account issues, or feature requests:
                  </p>
                  <p className="text-blue-800 font-medium">
                    Email: support@jointally.app
                  </p>
                </div>

                <div className="bg-green-50 p-6 rounded-lg">
                  <h3 className="text-lg font-semibold text-green-800 mb-2">
                    Privacy & Legal
                  </h3>
                  <p className="text-green-700 mb-3">
                    For privacy concerns, data requests, or legal matters:
                  </p>
                  <p className="text-green-800 font-medium">
                    Email: privacy@jointally.app
                  </p>
                </div>

                <div className="bg-purple-50 p-6 rounded-lg">
                  <h3 className="text-lg font-semibold text-purple-800 mb-2">
                    Business & Partnerships
                  </h3>
                  <p className="text-purple-700 mb-3">
                    For business inquiries, partnerships, or press:
                  </p>
                  <p className="text-purple-800 font-medium">
                    Email: hello@jointally.app
                  </p>
                </div>
              </div>
            </section>

            {/* Response Time */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Response Time
              </h2>
              <div className="bg-gray-50 p-6 rounded-lg">
                <ul className="space-y-3 text-gray-700">
                  <li className="flex items-start">
                    <span className="text-green-600 mr-2">✓</span>
                    <span>
                      <strong>General Support:</strong> Within 24-48 hours
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-green-600 mr-2">✓</span>
                    <span>
                      <strong>Privacy & Legal:</strong> Within 72 hours
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-green-600 mr-2">✓</span>
                    <span>
                      <strong>Business Inquiries:</strong> Within 1-2 business
                      days
                    </span>
                  </li>
                </ul>
              </div>
            </section>

            {/* FAQ Link */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Quick Help
              </h2>
              <div className="bg-yellow-50 p-6 rounded-lg">
                <h3 className="text-lg font-semibold text-yellow-800 mb-2">
                  Check Our FAQ First
                </h3>
                <p className="text-yellow-700 mb-4">
                  Many common questions are answered in our frequently asked
                  questions section.
                </p>
                <Link
                  href="/#faq"
                  className="inline-block bg-yellow-600 text-white px-4 py-2 rounded-lg hover:bg-yellow-700 transition-colors"
                >
                  View FAQ
                </Link>
              </div>
            </section>

            {/* Office Hours */}
            <section>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">
                Office Hours
              </h2>
              <div className="bg-gray-50 p-6 rounded-lg">
                <p className="text-gray-700 mb-3">
                  <strong>Monday - Friday:</strong> 9:00 AM - 6:00 PM PST
                </p>
                <p className="text-gray-700 mb-3">
                  <strong>Saturday:</strong> 10:00 AM - 4:00 PM PST
                </p>
                <p className="text-gray-700">
                  <strong>Sunday:</strong> Closed
                </p>
                <p className="text-sm text-gray-600 mt-3">
                  We typically respond to emails outside of office hours, but
                  response times may be longer.
                </p>
              </div>
            </section>

            {/* Footer */}
            <div className="border-t pt-6 mt-8">
              <div className="flex justify-center space-x-4">
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
