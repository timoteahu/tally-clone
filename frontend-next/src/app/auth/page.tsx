"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { API_BASE_URL } from "../../utils/api";

export default function AuthPage() {
  const [phoneNumber, setPhoneNumber] = useState("");
  const [verificationCode, setVerificationCode] = useState("");
  const [step, setStep] = useState<"phone" | "verify">("phone");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const router = useRouter();

  const handlePhoneSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError("");

    try {
      const response = await fetch(`${API_BASE_URL}/auth/send-verification`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ phone_number: phoneNumber }),
      });

      if (!response.ok) {
        throw new Error("Failed to send verification code");
      }

      setStep("verify");
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const handleVerificationSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError("");

    try {
      const response = await fetch(`${API_BASE_URL}/auth/token`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          phone_number: phoneNumber,
          verification_code: verificationCode,
        }),
      });

      if (!response.ok) {
        throw new Error("Invalid verification code");
      }

      const data = await response.json();
      localStorage.setItem("authToken", data.access_token);
      router.push("/setup-payment");
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-black flex items-center justify-center">
      <div className="bg-black border border-white/10 rounded-lg p-8 max-w-md w-full">
        <h1 className="text-3xl font-bold text-white mb-8 text-center">
          Tally
        </h1>

        {error && (
          <div className="bg-white/5 border border-white/10 rounded-lg p-4 mb-6">
            <p className="text-red-400 text-sm">{error}</p>
          </div>
        )}

        {step === "phone" ? (
          <form onSubmit={handlePhoneSubmit} className="space-y-6">
            <div>
              <label
                htmlFor="phone"
                className="block text-sm font-medium text-white/80 mb-2"
              >
                Phone Number
              </label>
              <input
                type="tel"
                id="phone"
                value={phoneNumber}
                onChange={(e) => setPhoneNumber(e.target.value)}
                className="w-full px-4 py-2 bg-black border border-white/10 rounded-lg text-white focus:ring-2 focus:ring-white/20 focus:border-transparent placeholder:text-white/40"
                placeholder="+1 (555) 555-5555"
                required
              />
            </div>
            <button
              type="submit"
              disabled={loading}
              className="w-full bg-white text-black py-3 px-4 rounded-lg font-medium
                       hover:bg-white/90 focus:outline-none focus:ring-2 focus:ring-offset-2 
                       focus:ring-white/20 disabled:opacity-50 disabled:cursor-not-allowed transition-all"
            >
              {loading ? "Sending..." : "Send Verification Code"}
            </button>
          </form>
        ) : (
          <form onSubmit={handleVerificationSubmit} className="space-y-6">
            <div>
              <label
                htmlFor="code"
                className="block text-sm font-medium text-white/80 mb-2"
              >
                Verification Code
              </label>
              <input
                type="text"
                id="code"
                value={verificationCode}
                onChange={(e) => setVerificationCode(e.target.value)}
                className="w-full px-4 py-2 bg-black border border-white/10 rounded-lg text-white focus:ring-2 focus:ring-white/20 focus:border-transparent placeholder:text-white/40"
                placeholder="Enter 6-digit code"
                required
              />
            </div>
            <button
              type="submit"
              disabled={loading}
              className="w-full bg-white text-black py-3 px-4 rounded-lg font-medium
                       hover:bg-white/90 focus:outline-none focus:ring-2 focus:ring-offset-2 
                       focus:ring-white/20 disabled:opacity-50 disabled:cursor-not-allowed transition-all"
            >
              {loading ? "Verifying..." : "Verify Code"}
            </button>
            <button
              type="button"
              onClick={() => setStep("phone")}
              className="w-full text-white/60 hover:text-white text-sm"
            >
              Back to Phone Number
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
