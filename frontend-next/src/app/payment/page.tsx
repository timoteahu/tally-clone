"use client";
import dynamic from "next/dynamic";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { PaymentForm } from "../../components/PaymentForm";
import { API_BASE_URL } from "../../utils/api";

const StripeConnectOnboarding = dynamic(
  () => import("../../components/StripeConnectOnboarding"),
  { ssr: false },
);
const WithdrawFunds = dynamic(() => import("../../components/WithdrawFunds"), {
  ssr: false,
});

export default function PaymentManagementPage() {
  const router = useRouter();
  const [card, setCard] = useState<any>(null);
  const [showForm, setShowForm] = useState(false);
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [stripeConnectStatus, setStripeConnectStatus] = useState<{
    hasAccount: boolean;
    isEnabled: boolean;
  } | null>(null);

  // Fetch current card info
  useEffect(() => {
    const fetchCard = async () => {
      console.log("[Payment] fetchCard called");
      console.log("[Payment] fetchCard called");
      setLoading(true);
      setError(null);
      const authToken = localStorage.getItem("authToken");
      console.log("[Payment] authToken:", authToken);
      console.log("[Payment] authToken:", authToken);
      if (!authToken) {
        setError("You must be logged in.");
        setCard(null);
        setCard(null);
        setLoading(false);
        // Redirect to login page
        router.push("/auth");
        return;
      }
      try {
        const res = await fetch(
          `${API_BASE_URL}/payments/get-user-payment-method`,
          {
            headers: {
              Authorization: `Bearer ${authToken}`,
              "ngrok-skip-browser-warning": "true",
            },
          },
        );
        console.log("[Payment] Response status:", res.status);
        if (!res.ok) {
          // Try to parse error message from backend
          let errorMsg = "Failed to fetch card info";
          try {
            const errData = await res.json();
            console.log("[Payment] Error response:", errData);
            if (
              errData.detail === "Payment method not found" ||
              errData.detail === "Stripe customer ID not found"
            ) {
              errorMsg = "No card on file.";
            } else if (errData.detail === "User not found") {
              errorMsg = "You must be logged in.";
            } else {
              errorMsg = errData.detail || errorMsg;
            }
          } catch (e) {
            console.log("[Payment] Error parsing error response:", e);
          }
          setError(errorMsg);
          setCard(null);
          setLoading(false);
          return;
        }
        const data = await res.json();
        console.log("[Payment] Success response:", data);
        if (data.payment_method && data.payment_method.card) {
          setCard(data.payment_method.card);
        } else {
          setCard(null);
          setError("No card on file.");
        }
      } catch (err) {
        console.log("[Payment] Fetch error:", err);
        setError("An error occurred");
        setCard(null);
      }
      setLoading(false);
    };
    fetchCard();
  }, [showForm]); // refetch after form closes

  // Fetch Stripe Connect status
  useEffect(() => {
    const fetchStripeConnectStatus = async () => {
      const authToken = localStorage.getItem("authToken");
      if (!authToken) return;

      try {
        const res = await fetch(
          `${API_BASE_URL}/payments/connect/account-status`,
          {
            headers: {
              Authorization: `Bearer ${authToken}`,
              "ngrok-skip-browser-warning": "true",
            },
          },
        );

        if (res.ok) {
          const data = await res.json();
          setStripeConnectStatus({
            hasAccount: !!data.account_id,
            isEnabled: data.is_fully_enabled || false,
          });
        } else {
          setStripeConnectStatus({
            hasAccount: false,
            isEnabled: false,
          });
        }
      } catch (err) {
        console.log("[Payment] Error fetching Stripe Connect status:", err);
        setStripeConnectStatus({
          hasAccount: false,
          isEnabled: false,
        });
      }
    };

    fetchStripeConnectStatus();
  }, []);

  // Fetch setup intent when showing form
  useEffect(() => {
    if (!showForm) return;
    const fetchSetupIntent = async () => {
      setClientSecret(null);
      const authToken = localStorage.getItem("authToken");
      if (!authToken) return;
      console.log("Fetching setup intent...");
      const res = await fetch(`${API_BASE_URL}/payments/create-setup-intent`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${authToken}`,
          "Content-Type": "application/json",
          "ngrok-skip-browser-warning": "true",
        },
      });
      if (!res.ok) {
        console.log("Failed to fetch setup intent");
        return;
      }
      const data = await res.json();
      console.log("Fetched setup intent:", data);
      setClientSecret(data.clientSecret);
    };
    fetchSetupIntent();
  }, [showForm]);

  return (
    <div className="min-h-screen bg-black text-white py-12 px-4">
      <div className="max-w-2xl mx-auto space-y-10">
        <h1 className="text-3xl font-bold mb-6">Manage Payments</h1>
        <section className="bg-white/10 border border-white/20 rounded-2xl p-8 shadow-lg mb-8">
          <h2 className="text-xl font-semibold flex items-center gap-2 mb-4">
            Payment Method
          </h2>
          {loading ? (
            <div className="flex items-center gap-2">
              <span className="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-600"></span>
              <span>Loading...</span>
            </div>
          ) : error ? (
            <div className="bg-red-100 text-red-700 px-4 py-2 rounded mb-2">
              {error}
            </div>
          ) : card ? (
            <div className="flex items-center gap-16 py-4">
              <div className="flex items-center gap-6">
                <div className="border border-blue-200 rounded-xl py-6 px-6 shadow-md flex items-center gap-6 min-w-[280px]">
                  {/* Card brand logo placeholder */}

                  <div className="space-y-2">
                    <div className="text-xl font-bold text-white tracking-widest">
                      •••• {card.last4}
                    </div>
                    <div className="text-base text-blue-100 capitalize">
                      {card.brand}
                    </div>
                  </div>

                  <span className="ml-auto border border-blue-200 text-white text-xs px-4 py-2 rounded-full">
                    Expires {card.exp_month}/{card.exp_year}
                  </span>
                </div>
              </div>
              <button
                className="px-8 py-3 border border-blue-200 hover:border-blue-400 rounded-lg text-white font-semibold shadow transition ml-8"
                onClick={() => setShowForm(true)}
                style={{ minWidth: 120 }}
              >
                change payment method
              </button>
            </div>
          ) : (
            <div className="text-gray-300">No card on file.</div>
          )}
          {showForm && clientSecret && (
            <>
              <div className="my-6 border-t border-white/20" />
              <div className="mt-6">
                <PaymentForm clientSecret={clientSecret} />
                <button
                  className="mt-4 px-4 py-2 bg-gray-600 rounded text-white"
                  onClick={() => setShowForm(false)}
                >
                  Cancel
                </button>
              </div>
            </>
          )}
        </section>

        {/* Stripe Connect Section */}
        <section className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-3xl p-8 mb-8">
          <div className="flex items-center gap-4 mb-6">
            <div className="w-8 h-8 bg-white/10 rounded-full flex items-center justify-center">
              <svg
                className="w-4 h-4 text-white"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={1.5}
                  d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
                />
              </svg>
            </div>
            <h2
              className="text-2xl font-normal"
              style={{ fontFamily: "var(--font-eb-garamond), serif" }}
            >
              stripe connect
            </h2>
          </div>
          <p
            className="text-white/80 mb-6 leading-relaxed"
            style={{ fontFamily: "var(--font-eb-garamond), serif" }}
          >
            set up your account to receive payments when your friends miss their
            habits
          </p>

          <StripeConnectOnboarding />
        </section>

        {/* Payment History Section */}
        <section className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-3xl p-8 mb-8">
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-4">
              <div className="w-8 h-8 bg-white/10 rounded-full flex items-center justify-center">
                <svg
                  className="w-4 h-4 text-white"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={1.5}
                    d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"
                  />
                </svg>
              </div>
              <h2
                className="text-2xl font-normal"
                style={{ fontFamily: "var(--font-eb-garamond), serif" }}
              >
                payment history
              </h2>
            </div>
            <Link
              href="/payment-history"
              className="text-white/60 hover:text-white transition-colors flex items-center gap-2"
            >
              <span className="text-sm">view all</span>
              <svg
                className="w-4 h-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={1.5}
                  d="M9 5l7 7-7 7"
                />
              </svg>
            </Link>
          </div>
          <p
            className="text-white/80 mb-6 leading-relaxed"
            style={{ fontFamily: "var(--font-eb-garamond), serif" }}
          >
            track your payments and see how much you've gained or lost from habits
          </p>
          <Link
            href="/payment-history"
            className="inline-flex items-center justify-center px-6 py-3 bg-white/10 hover:bg-white/20 text-white font-medium rounded-full transition-all duration-300"
            style={{ fontFamily: "var(--font-eb-garamond), serif" }}
          >
            view payment history
          </Link>
        </section>

        {stripeConnectStatus?.isEnabled && (
          <section className="bg-white/5 border border-white/10 rounded-lg p-8 space-y-6">
            <h2 className="text-xl font-semibold mb-2">Withdraw Funds</h2>
            <WithdrawFunds />
          </section>
        )}
      </div>
    </div>
  );
}
