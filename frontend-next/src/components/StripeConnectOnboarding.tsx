"use client";
import { useState } from "react";
import { API_BASE_URL } from "../utils/api";

export default function StripeConnectOnboarding() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleConnect = async () => {
    setLoading(true);
    setError(null);
    try {
      // 1. Create account and get onboarding link from backend
      const authToken =
        typeof window !== "undefined"
          ? localStorage.getItem("authToken")
          : null;
      if (!authToken) {
        setError("You must be logged in.");
        setLoading(false);
        return;
      }
      const res = await fetch(
        `${API_BASE_URL}/payments/connect/create-account`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${authToken}` },
        },
      );
      if (!res.ok) throw new Error("Failed to create Stripe account");
      const { account_id } = await res.json();

      const linkRes = await fetch(
        `${API_BASE_URL}/payments/connect/create-account-link`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${authToken}`,
          },
          body: JSON.stringify({
            account_id: account_id.trim(),
            refresh_url: "https://jointally.app/stripe-refresh",
            return_url: "https://jointally.app/stripe-return",
          }),
        },
      );
      if (!linkRes.ok) throw new Error("Failed to create onboarding link");
      const { url } = await linkRes.json();
      window.location.href = url;
    } catch (err: any) {
      setError(err.message || "An error occurred");
      setLoading(false);
    }
  };

  return (
    <div className="space-y-2">
      <button
        onClick={handleConnect}
        disabled={loading}
        className="w-full bg-gradient-to-r from-blue-600 to-purple-600 text-white py-3 px-4 rounded-lg font-medium hover:from-blue-700 hover:to-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition-all flex items-center justify-center space-x-2"
      >
        {loading ? "Connecting..." : "Connect Stripe Account"}
      </button>
      {error && <div className="text-red-500 text-sm">{error}</div>}
    </div>
  );
}
