"use client";

import { useEffect, useState, Suspense } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useSearchParams } from "next/navigation";

interface Penalty {
  id: string;
  amount: number;
  penalty_date: string;
  habit_id: string;
  user_id: string;
  is_paid: boolean;
}

function CheckoutContent() {
  const [error, setError] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const [penalty, setPenalty] = useState<Penalty | null>(null);
  const [processing, setProcessing] = useState(false);
  const searchParams = useSearchParams();
  const router = useRouter();
  const penaltyId = searchParams.get("penalty_id");

  useEffect(() => {
    const fetchPenalty = async () => {
      const authToken = localStorage.getItem("authToken");
      if (!authToken) {
        router.push("/auth");
        return;
      }

      if (!penaltyId) {
        setError("No penalty ID provided");
        setLoading(false);
        return;
      }

      try {
        const penaltyResponse = await fetch(
          `http://localhost:8000/api/penalties/${penaltyId}`,
          {
            headers: {
              Authorization: `Bearer ${authToken}`,
            },
          },
        );
        if (!penaltyResponse.ok) {
          throw new Error("Failed to fetch penalty details");
        }
        const penaltyData = await penaltyResponse.json();
        setPenalty(penaltyData);
      } catch (err) {
        setError(err instanceof Error ? err.message : "An error occurred");
      } finally {
        setLoading(false);
      }
    };

    fetchPenalty();
  }, [penaltyId, router]);

  const handlePayment = async () => {
    if (!penalty) return;

    setProcessing(true);
    setError("");

    try {
      const authToken = localStorage.getItem("authToken");
      const response = await fetch(
        "http://localhost:8000/api/payments/charge",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${authToken}`,
          },
          body: JSON.stringify({
            penalty_id: penalty.id,
            amount: Math.round(penalty.amount * 100), // Convert to cents
          }),
        },
      );

      if (!response.ok) {
        throw new Error("Failed to process payment");
      }

      router.push("/payment/success");
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
      setProcessing(false);
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-white via-blue-100 to-purple-200">
        <div className="relative w-16 h-16">
          <div className="absolute top-0 left-0 w-full h-full border-4 border-blue-200 rounded-full animate-pulse"></div>
          <div className="absolute top-0 left-0 w-full h-full border-4 border-blue-600 rounded-full animate-spin border-t-transparent"></div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-white via-blue-100 to-purple-200">
        <div className="bg-white p-8 rounded-lg shadow-lg max-w-md w-full">
          <h2 className="text-2xl font-bold text-red-600 mb-4">Error</h2>
          <p className="text-gray-600 mb-6">{error}</p>
          <Link href="/penalties" className="text-blue-600 hover:text-blue-800">
            Return to Penalties
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-white via-blue-100 to-purple-200">
      {/* Navigation */}
      <nav className="sticky top-0 z-50 bg-white/80 backdrop-blur-lg border-b border-purple-200 shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between h-16 items-center">
            <Link
              href="/"
              className="text-2xl font-bold bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent"
            >
              Joy Thief
            </Link>
          </div>
        </div>
      </nav>

      <div className="max-w-4xl mx-auto px-4 py-16">
        <div className="bg-white/90 backdrop-blur-lg rounded-2xl shadow-xl border border-purple-200 p-8 transform transition-all duration-300 hover:shadow-2xl">
          <h1 className="text-3xl font-bold bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent mb-8">
            Complete Your Purchase
          </h1>

          {/* Order Summary */}
          <div className="mb-8 p-8 bg-gradient-to-br from-blue-50 to-purple-50 rounded-2xl border border-purple-200 shadow-inner">
            <h2 className="text-xl font-bold text-gray-900 mb-6">
              Order Summary
            </h2>
            <div className="space-y-4">
              <div className="flex justify-between items-center">
                <span className="text-gray-600 text-lg">Penalty Payment</span>
                <span className="text-gray-900 font-bold text-lg">
                  ${penalty?.amount.toFixed(2)}
                </span>
              </div>
              <div className="border-t-2 border-purple-100 my-4"></div>
              <div className="flex justify-between items-center">
                <span className="text-gray-900 font-bold text-lg">Total</span>
                <span className="text-2xl font-bold bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent">
                  ${penalty?.amount.toFixed(2)}
                </span>
              </div>
            </div>
          </div>

          {/* Payment Button */}
          <button
            onClick={handlePayment}
            disabled={processing}
            className="w-full bg-gradient-to-r from-blue-600 to-purple-600 text-white py-3 px-4 rounded-lg font-medium
                     hover:from-blue-700 hover:to-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 
                     focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition-all
                     flex items-center justify-center space-x-2"
          >
            {processing ? (
              <>
                <svg
                  className="animate-spin -ml-1 mr-3 h-5 w-5 text-white"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle
                    className="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    strokeWidth="4"
                  ></circle>
                  <path
                    className="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  ></path>
                </svg>
                <span>Processing...</span>
              </>
            ) : (
              "Pay Now"
            )}
          </button>
        </div>
      </div>
    </div>
  );
}

export default function CheckoutPage() {
  return (
    <Suspense
      fallback={
        <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-white via-blue-100 to-purple-200">
          <div className="relative w-16 h-16">
            <div className="absolute top-0 left-0 w-full h-full border-4 border-blue-200 rounded-full animate-pulse"></div>
            <div className="absolute top-0 left-0 w-full h-full border-4 border-blue-600 rounded-full animate-spin border-t-transparent"></div>
          </div>
        </div>
      }
    >
      <CheckoutContent />
    </Suspense>
  );
}
