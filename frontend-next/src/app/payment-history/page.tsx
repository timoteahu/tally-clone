"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { API_BASE_URL } from "../../utils/api";

interface PaymentHistoryItem {
  id: string;
  amount: number;
  date: string;
  is_paid: boolean;
  payment_status: string;
  reason: string;
}

interface PaymentStats {
  weekly_payments: number;
  monthly_payments: number;
  total_payments: number;
  daily_payments: number[];
  week_days: string[];
  unpaid_penalties: number;
  processing_payments: number;
  payment_history: PaymentHistoryItem[];
}

export default function PaymentHistoryPage() {
  const router = useRouter();
  const [stats, setStats] = useState<PaymentStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchPaymentStats = async () => {
      const authToken = localStorage.getItem("authToken");
      if (!authToken) {
        router.push("/auth");
        return;
      }

      try {
        const res = await fetch(`${API_BASE_URL}/sync/payment-stats`, {
          headers: {
            Authorization: `Bearer ${authToken}`,
            "ngrok-skip-browser-warning": "true",
          },
        });

        if (!res.ok) {
          throw new Error("Failed to fetch payment stats");
        }

        const data = await res.json();
        setStats(data);
      } catch (err) {
        console.error("Error fetching payment stats:", err);
        setError("Failed to load payment history");
      } finally {
        setLoading(false);
      }
    };

    fetchPaymentStats();
  }, [router]);

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr);
    return date.toLocaleDateString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
    });
  };

  const getStatusColor = (item: PaymentHistoryItem) => {
    if (item.is_paid) return "text-green-400";
    if (item.payment_status === "processing") return "text-orange-400";
    return "text-red-400";
  };

  const getStatusText = (item: PaymentHistoryItem) => {
    if (item.is_paid) return "Paid";
    if (item.payment_status === "processing") return "Processing";
    return "Unpaid";
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-black text-white flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white mx-auto mb-4"></div>
          <p>Loading payment history...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen bg-black text-white flex items-center justify-center">
        <div className="text-center">
          <p className="text-red-400 mb-4">{error}</p>
          <Link href="/payment" className="text-white/60 hover:text-white">
            Back to Payment
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-black text-white">
      {/* Header */}
      <div className="sticky top-0 bg-black/80 backdrop-blur-md border-b border-white/10 z-10">
        <div className="max-w-4xl mx-auto px-4 py-4 flex items-center justify-between">
          <Link
            href="/payment"
            className="flex items-center space-x-2 text-white/60 hover:text-white transition-colors"
          >
            <svg
              className="w-5 h-5"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={1.5}
                d="M15 19l-7-7 7-7"
              />
            </svg>
            <span>Back</span>
          </Link>
          <h1
            className="text-2xl font-normal"
            style={{ fontFamily: "var(--font-eb-garamond), serif" }}
          >
            payment history
          </h1>
          <div className="w-20"></div>
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 py-8 space-y-8">
        {/* Summary Cards */}
        <div className="space-y-4">
          <h2
            className="text-sm text-white/60 uppercase tracking-wider mb-4"
            style={{ fontFamily: "var(--font-eb-garamond), serif" }}
          >
            summary
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <div className="bg-white/5 border border-white/10 rounded-2xl p-6">
              <p className="text-sm text-white/60 mb-1">Total Paid</p>
              <p className="text-2xl font-semibold text-green-400">
                ${(stats?.total_payments ?? 0).toFixed(2)}
              </p>
              <p className="text-xs text-white/40 mt-1">All time</p>
            </div>
            
            <div className="bg-white/5 border border-white/10 rounded-2xl p-6">
              <p className="text-sm text-white/60 mb-1">Unpaid</p>
              <p className="text-2xl font-semibold text-red-400">
                ${(stats?.unpaid_penalties ?? 0).toFixed(2)}
              </p>
              <p className="text-xs text-white/40 mt-1">Current balance</p>
            </div>

            {stats?.processing_payments && stats?.processing_payments > 0 && (
              <div className="bg-white/5 border border-white/10 rounded-2xl p-6">
                <p className="text-sm text-white/60 mb-1">Processing</p>
                <p className="text-2xl font-semibold text-orange-400">
                  ${(stats?.processing_payments ?? 0).toFixed(2)}
                </p>
                <p className="text-xs text-white/40 mt-1">In progress</p>
              </div>
            )}

            <div className="bg-white/5 border border-white/10 rounded-2xl p-6">
              <p className="text-sm text-white/60 mb-1">This Week</p>
              <p className="text-2xl font-semibold text-white">
                ${(stats?.weekly_payments ?? 0).toFixed(2)}
              </p>
              <p className="text-xs text-white/40 mt-1">Sun - Sat</p>
            </div>

            <div className="bg-white/5 border border-white/10 rounded-2xl p-6">
              <p className="text-sm text-white/60 mb-1">This Month</p>
              <p className="text-2xl font-semibold text-white">
                ${(stats?.monthly_payments ?? 0).toFixed(2)}
              </p>
              <p className="text-xs text-white/40 mt-1">
                {new Date().toLocaleDateString("en-US", { month: "long" })}
              </p>
            </div>
          </div>
        </div>

        {/* Weekly Chart */}
        {stats?.daily_payments?.some(amount => amount > 0) && (
          <div className="space-y-4">
            <h2
              className="text-sm text-white/60 uppercase tracking-wider"
              style={{ fontFamily: "var(--font-eb-garamond), serif" }}
            >
              this week
            </h2>
            <div className="bg-white/5 border border-white/10 rounded-2xl p-6">
              <div className="flex items-end justify-between h-32 gap-2">
                {stats?.daily_payments?.map((amount, index) => {
                  const maxAmount = Math.max(...(stats?.daily_payments ?? []), 1);
                  const heightPercent = (amount / maxAmount) * 100;
                  return (
                    <div key={index} className="flex-1 flex flex-col items-center">
                      <div className="w-full bg-white/10 rounded-t relative h-24 flex items-end">
                        <div
                          className="w-full bg-gradient-to-t from-blue-500 to-blue-400 rounded-t transition-all duration-300"
                          style={{ height: `${heightPercent}%` }}
                        />
                      </div>
                      <p className="text-xs text-white/40 mt-2">
                        {stats?.week_days?.[index]}
                      </p>
                      {amount > 0 && (
                        <p className="text-xs text-white/60 mt-1">
                          ${amount.toFixed(0)}
                        </p>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        )}

        {/* Payment History */}
        <div className="space-y-4">
          <h2
            className="text-sm text-white/60 uppercase tracking-wider"
            style={{ fontFamily: "var(--font-eb-garamond), serif" }}
          >
            payment history
          </h2>
          <div className="bg-white/5 border border-white/10 rounded-2xl overflow-hidden">
            {stats?.payment_history?.length === 0 ? (
              <div className="p-12 text-center">
                <div className="w-16 h-16 bg-white/10 rounded-full flex items-center justify-center mx-auto mb-4">
                  <svg
                    className="w-8 h-8 text-white/30"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={1.5}
                      d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z"
                    />
                  </svg>
                </div>
                <p className="text-white/60 mb-2">No payment history</p>
                <p className="text-sm text-white/40">
                  Your payments will appear here
                </p>
              </div>
            ) : (
              <div className="divide-y divide-white/10">
                {stats?.payment_history?.map((payment) => (
                  <div key={payment.id} className="p-4 hover:bg-white/5 transition-colors">
                    <div className="flex items-start justify-between">
                      <div className="flex-1">
                        <p className="text-white mb-1">{payment.reason}</p>
                        <p className="text-sm text-white/40">
                          {formatDate(payment.date)}
                        </p>
                      </div>
                      <div className="text-right ml-4">
                        <p className="text-white font-medium">
                          ${payment.amount.toFixed(2)}
                        </p>
                        <p className={`text-sm ${getStatusColor(payment)}`}>
                          {getStatusText(payment)}
                        </p>
                      </div>
                    </div>
                    
                    {/* Show transfer breakdown for paid penalties */}
                    {payment.is_paid && payment.amount > 0 && (
                      <div className="mt-3 pt-3 border-t border-white/10">
                        <div className="text-xs space-y-1">
                          <div className="flex justify-between text-white/60">
                            <span>Recipient payout:</span>
                            <span className="text-green-400/80">
                              ${(payment.amount * 0.85).toFixed(2)}
                            </span>
                          </div>
                          <div className="flex justify-between text-white/60">
                            <span>Platform fee (15%):</span>
                            <span className="text-blue-400/80">
                              ${(payment.amount * 0.15).toFixed(2)}
                            </span>
                          </div>
                        </div>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* How Payments Work */}
        <div className="space-y-4">
          <h2
            className="text-sm text-white/60 uppercase tracking-wider"
            style={{ fontFamily: "var(--font-eb-garamond), serif" }}
          >
            how payments work
          </h2>
          <div className="space-y-3">
            <div className="bg-white/5 border border-white/10 rounded-2xl p-4 flex items-start space-x-4">
              <div className="w-8 h-8 bg-blue-500/20 rounded-full flex items-center justify-center flex-shrink-0">
                <svg
                  className="w-4 h-4 text-blue-400"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z"
                  />
                </svg>
              </div>
              <div>
                <h3 className="text-white mb-1">efficient charging</h3>
                <p className="text-sm text-white/60">
                  penalties are charged when the total reaches $10, reducing transaction fees
                </p>
              </div>
            </div>

            <div className="bg-white/5 border border-white/10 rounded-2xl p-4 flex items-start space-x-4">
              <div className="w-8 h-8 bg-green-500/20 rounded-full flex items-center justify-center flex-shrink-0">
                <svg
                  className="w-4 h-4 text-green-400"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"
                  />
                </svg>
              </div>
              <div>
                <h3 className="text-white mb-1">instant transfers</h3>
                <p className="text-sm text-white/60">
                  85% goes to recipients immediately, 15% platform fee covers processing
                </p>
              </div>
            </div>

            <div className="bg-white/5 border border-white/10 rounded-2xl p-4 flex items-start space-x-4">
              <div className="w-8 h-8 bg-purple-500/20 rounded-full flex items-center justify-center flex-shrink-0">
                <svg
                  className="w-4 h-4 text-purple-400"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
                  />
                </svg>
              </div>
              <div>
                <h3 className="text-white mb-1">secure processing</h3>
                <p className="text-sm text-white/60">
                  all transactions processed securely through stripe with industry-leading protection
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}