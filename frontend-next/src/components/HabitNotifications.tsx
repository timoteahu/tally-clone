"use client";

import { useState, useEffect } from "react";
import { API_BASE_URL } from "../utils/api";

interface ScheduledNotification {
  id: string;
  notification_type: string;
  scheduled_time: string;
  title: string;
  message: string;
  habit_id: string;
  sent: boolean;
  skipped: boolean;
}

interface NotificationStats {
  total_scheduled: number;
  total_sent: number;
  total_pending: number;
  delivery_rate: number;
  by_notification_type: Record<string, number>;
}

export default function HabitNotifications() {
  const [notifications, setNotifications] = useState<ScheduledNotification[]>([]);
  const [stats, setStats] = useState<NotificationStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [timeRange, setTimeRange] = useState(24); // Default 24 hours

  const fetchNotifications = async () => {
    const authToken = localStorage.getItem("authToken");
    if (!authToken) {
      setError("You must be logged in to view notifications.");
      setLoading(false);
      return;
    }

    try {
      // Get user ID from auth token (you might need to decode JWT or make API call)
      // For now, we'll make a call to get current user
      const userResponse = await fetch(`${API_BASE_URL}/users/me`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      
      if (!userResponse.ok) {
        throw new Error("Failed to get user info");
      }
      
      const userData = await userResponse.json();
      const userId = userData.id;

      // Fetch upcoming notifications
      const notificationsResponse = await fetch(
        `${API_BASE_URL}/habit-notifications/scheduled/${userId}/upcoming?hours=${timeRange}`,
        {
          headers: { Authorization: `Bearer ${authToken}` },
        }
      );

      if (!notificationsResponse.ok) {
        throw new Error("Failed to fetch notifications");
      }

      const notificationsData = await notificationsResponse.json();
      setNotifications(notificationsData.notifications || []);

      // Fetch notification stats
      const statsResponse = await fetch(
        `${API_BASE_URL}/habit-notifications/stats/${userId}`,
        {
          headers: { Authorization: `Bearer ${authToken}` },
        }
      );

      if (statsResponse.ok) {
        const statsData = await statsResponse.json();
        setStats(statsData);
      }

    } catch (err: any) {
      setError(err.message || "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const sendTestNotification = async () => {
    const authToken = localStorage.getItem("authToken");
    if (!authToken) return;

    try {
      const response = await fetch(`${API_BASE_URL}/habit-notifications/test-send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${authToken}` },
      });

      if (response.ok) {
        alert("Test notification sent! Check your device.");
      } else {
        alert("Failed to send test notification.");
      }
    } catch (err) {
      alert("Error sending test notification.");
    }
  };

  useEffect(() => {
    fetchNotifications();
  }, [timeRange]);

  const formatDateTime = (isoString: string) => {
    const date = new Date(isoString);
    return date.toLocaleString();
  };

  const getNotificationTypeIcon = (type: string) => {
    const icons: Record<string, string> = {
      alarm_checkin_window: "🕐",
      alarm_wake_up: "⏰",
      alarm_missed: "😴",
      habit_reminder_12h: "📅",
      habit_reminder_6h: "⏰",
      habit_reminder_1h: "🚨",
      habit_missed: "❌",
    };
    return icons[type] || "📱";
  };

  const getNotificationTypeColor = (type: string) => {
    const colors: Record<string, string> = {
      alarm_checkin_window: "backdrop-blur-sm bg-blue-500/30 border border-blue-400/50 text-blue-200",
      alarm_wake_up: "backdrop-blur-sm bg-yellow-500/30 border border-yellow-400/50 text-yellow-200",
      alarm_missed: "backdrop-blur-sm bg-red-500/30 border border-red-400/50 text-red-200",
      habit_reminder_12h: "backdrop-blur-sm bg-green-500/30 border border-green-400/50 text-green-200",
      habit_reminder_6h: "backdrop-blur-sm bg-orange-500/30 border border-orange-400/50 text-orange-200",
      habit_reminder_1h: "backdrop-blur-sm bg-red-500/30 border border-red-400/50 text-red-200",
      habit_missed: "backdrop-blur-sm bg-white/20 border border-white/40 text-white/80",
    };
    return colors[type] || "backdrop-blur-sm bg-white/20 border border-white/40 text-white/80";
  };

  if (loading) {
    return (
      <div className="backdrop-blur-xl bg-white/10 border border-white/20 rounded-lg shadow-lg p-6">
        <div className="animate-pulse">
          <div className="h-6 bg-white/20 rounded w-1/3 mb-4"></div>
          <div className="space-y-3">
            {[1, 2, 3].map((i) => (
              <div key={i} className="h-16 bg-white/20 rounded"></div>
            ))}
          </div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="backdrop-blur-xl bg-white/10 border border-white/20 rounded-lg shadow-lg p-6">
        <div className="text-red-400">
          <h3 className="text-lg font-semibold mb-2 text-white">Error</h3>
          <p className="text-white/80">{error}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header with controls */}
      <div className="backdrop-blur-xl bg-white/10 border border-white/20 rounded-lg shadow-lg p-6">
        <div className="flex justify-between items-center mb-4">
          <h2 className="text-2xl font-bold text-white">Habit Notifications</h2>
          <div className="flex gap-3">
            <select
              value={timeRange}
              onChange={(e) => setTimeRange(Number(e.target.value))}
              className="px-3 py-2 backdrop-blur-md bg-white/20 border border-white/30 rounded-lg focus:outline-none focus:ring-2 focus:ring-white/50 text-white"
            >
              <option value={24}>Next 24 hours</option>
              <option value={48}>Next 48 hours</option>
              <option value={168}>Next week</option>
            </select>
            <button
              onClick={sendTestNotification}
              className="px-4 py-2 backdrop-blur-md bg-white/20 border border-white/30 text-white rounded-lg hover:bg-white/30 focus:outline-none focus:ring-2 focus:ring-white/50 transition-all"
            >
              Test Notification
            </button>
          </div>
        </div>

        {/* Stats */}
        {stats && (
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <div className="backdrop-blur-md bg-blue-500/20 border border-blue-400/30 p-4 rounded-lg">
              <div className="text-2xl font-bold text-blue-300">{stats.total_pending}</div>
              <div className="text-sm text-blue-200">Pending</div>
            </div>
            <div className="backdrop-blur-md bg-green-500/20 border border-green-400/30 p-4 rounded-lg">
              <div className="text-2xl font-bold text-green-300">{stats.total_sent}</div>
              <div className="text-sm text-green-200">Sent (7 days)</div>
            </div>
            <div className="backdrop-blur-md bg-purple-500/20 border border-purple-400/30 p-4 rounded-lg">
              <div className="text-2xl font-bold text-purple-300">{stats.delivery_rate}%</div>
              <div className="text-sm text-purple-200">Delivery Rate</div>
            </div>
            <div className="backdrop-blur-md bg-white/20 border border-white/30 p-4 rounded-lg">
              <div className="text-2xl font-bold text-white">{stats.total_scheduled}</div>
              <div className="text-sm text-white/80">Total (7 days)</div>
            </div>
          </div>
        )}
      </div>

      {/* Upcoming notifications */}
      <div className="backdrop-blur-xl bg-white/10 border border-white/20 rounded-lg shadow-lg p-6">
        <h3 className="text-lg font-semibold mb-4 text-white">
          Upcoming Notifications ({notifications.length})
        </h3>
        
        {notifications.length === 0 ? (
          <div className="text-center py-8 text-white/70">
            <div className="text-4xl mb-4">🔕</div>
            <p>No upcoming notifications in the selected time range.</p>
            <p className="text-sm mt-2">Notifications will appear here as your habits approach their due times.</p>
          </div>
        ) : (
          <div className="space-y-3">
            {notifications.map((notification) => (
              <div
                key={notification.id}
                className="backdrop-blur-md bg-white/10 border border-white/20 rounded-lg p-4 hover:bg-white/15 transition-all"
              >
                <div className="flex items-start justify-between">
                  <div className="flex items-start space-x-3">
                    <div className="text-2xl">
                      {getNotificationTypeIcon(notification.notification_type)}
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center space-x-2 mb-1">
                        <h4 className="font-semibold text-white">{notification.title}</h4>
                        <span
                          className={`px-2 py-1 text-xs rounded-full ${getNotificationTypeColor(
                            notification.notification_type
                          )}`}
                        >
                          {notification.notification_type.replace(/_/g, " ")}
                        </span>
                      </div>
                      <p className="text-white/80 text-sm mb-2">{notification.message}</p>
                      <div className="text-xs text-white/60">
                        Scheduled for: {formatDateTime(notification.scheduled_time)}
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Notification types legend */}
      <div className="backdrop-blur-xl bg-white/10 border border-white/20 rounded-lg shadow-lg p-6">
        <h3 className="text-lg font-semibold mb-4 text-white">Notification Types</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div className="space-y-2">
            <h4 className="font-medium text-white/90">Alarm Habits</h4>
            <div className="space-y-1 text-sm">
              <div className="flex items-center space-x-2">
                <span>🕐</span>
                <span className="text-white/80">Check-in window started (1 hour before)</span>
              </div>
              <div className="flex items-center space-x-2">
                <span>⏰</span>
                <span className="text-white/80">Wake up time (at alarm time)</span>
              </div>
              <div className="flex items-center space-x-2">
                <span>😴</span>
                <span className="text-white/80">Missed alarm (10 minutes after)</span>
              </div>
            </div>
          </div>
          <div className="space-y-2">
            <h4 className="font-medium text-white/90">Regular Habits</h4>
            <div className="space-y-1 text-sm">
              <div className="flex items-center space-x-2">
                <span>📅</span>
                <span className="text-white/80">Early reminder (12 hours before)</span>
              </div>
              <div className="flex items-center space-x-2">
                <span>⏰</span>
                <span className="text-white/80">Mid-day reminder (6 hours before)</span>
              </div>
              <div className="flex items-center space-x-2">
                <span>🚨</span>
                <span className="text-white/80">Final reminder (1 hour before)</span>
              </div>
              <div className="flex items-center space-x-2">
                <span>❌</span>
                <span className="text-white/80">Missed habit (when due)</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
} 