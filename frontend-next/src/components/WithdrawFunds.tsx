"use client";
import { useState, useEffect } from "react";
import { API_BASE_URL } from "../utils/api";

export default function WithdrawFunds() {
  const [balance, setBalance] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  useEffect(() => {
    const fetchBalance = async () => {
      setError(null);
      const authToken =
        typeof window !== "undefined"
          ? localStorage.getItem("authToken")
          : null;
      if (!authToken) {
        setError("You must be logged in.");
        return;
      }
      try {
        const res = await fetch(`${API_BASE_URL}/payments/connect/balance`, {
          headers: {
            Authorization: `Bearer ${authToken}`,
            "ngrok-skip-browser-warning": "true",
          },
        });
        if (!res.ok) throw new Error("Failed to fetch balance");
        const data = await res.json();
        setBalance(data.balance);
      } catch (err: any) {
        setError(err.message || "An error occurred");
      }
    };
    fetchBalance();
  }, []);

  const handleWithdraw = async () => {
    setLoading(true);
    setError(null);
    setSuccess(null);
    const authToken =
      typeof window !== "undefined" ? localStorage.getItem("authToken") : null;
    if (!authToken) {
      setError("You must be logged in.");
      setLoading(false);
      return;
    }
    try {
      const res = await fetch(`${API_BASE_URL}/payments/connect/withdraw`, {
        method: "POST",
        headers: { Authorization: `Bearer ${authToken}` },
      });
      if (!res.ok) throw new Error("Failed to withdraw funds");
      setSuccess("Withdrawal requested!");
      // Optionally refresh balance
      setBalance((b) => (b ? b - 5 : b)); // Assume $5 min withdrawal for demo
    } catch (err: any) {
      setError(err.message || "An error occurred");
    }
    setLoading(false);
  };

  return (
    <div className="space-y-2">
      <div>Available Balance: ${balance?.toFixed(2) ?? "0.00"}</div>
      <button
        onClick={handleWithdraw}
        disabled={loading || (balance ?? 0) < 5}
        className="w-full bg-gradient-to-r from-blue-600 to-purple-600 text-white py-3 px-4 rounded-lg font-medium hover:from-blue-700 hover:to-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition-all flex items-center justify-center space-x-2"
      >
        {loading ? "Withdrawing..." : "Withdraw Funds"}
      </button>
      {error && <div className="text-red-500 text-sm">{error}</div>}
      {success && <div className="text-green-500 text-sm">{success}</div>}
    </div>
  );
}
