#!/usr/bin/env python3
"""
Quick test script for GitHub timezone fixes.
Focuses on testing specific functions with clear output.
"""

import asyncio
import os
import sys
from datetime import datetime, date, time, timedelta
import pytz

# Add the parent directory to the path so we can import from the app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.config.database import get_async_supabase_client
from app.utils.github_commits import get_current_week_github_commits, get_user_timezone
from app.utils.weekly_habits import get_week_dates

async def quick_test_github_functions():
    """Quick test of GitHub timezone functions with clear output."""
    
    print("🚀 Quick GitHub Timezone Function Test")
    print("=" * 40)
    
    # Get database connection
    supabase = await get_async_supabase_client()
    
    try:
        # Get a sample of users with GitHub habits - using separate queries for better compatibility
        sample_result = await supabase.table("habits") \
            .select("user_id") \
            .eq("habit_type", "github_commits") \
            .eq("is_active", True) \
            .limit(5) \
            .execute()
        
        if not sample_result.data:
            print("❌ No GitHub habits found for testing")
            return
        
        # Get user timezones separately to avoid join issues
        user_ids = [habit['user_id'] for habit in sample_result.data]
        users_result = await supabase.table("users") \
            .select("id, timezone") \
            .in_("id", user_ids) \
            .execute()
        
        # Create a mapping of user_id to timezone
        user_timezones = {user['id']: user.get('timezone', 'UTC') for user in users_result.data}
        
        print(f"🧪 Testing with {len(sample_result.data)} sample users\n")
        
        for i, habit_data in enumerate(sample_result.data, 1):
            user_id = habit_data['user_id']
            stored_timezone = user_timezones.get(user_id, 'UTC')
            
            print(f"📋 Test {i}: User {user_id[:8]}...")
            print(f"   Stored timezone: {stored_timezone}")
            
            # Test get_user_timezone function
            try:
                retrieved_timezone = await get_user_timezone(supabase, user_id)
                print(f"   Retrieved timezone: {retrieved_timezone}")
                
                if retrieved_timezone == stored_timezone:
                    print(f"   ✅ Timezone retrieval matches")
                else:
                    print(f"   🔄 Timezone normalized: {stored_timezone} → {retrieved_timezone}")
                
                # Test timezone calculations
                user_tz = pytz.timezone(retrieved_timezone)
                user_now = datetime.now(user_tz)
                user_today = user_now.date()
                
                print(f"   Current user time: {user_now.strftime('%Y-%m-%d %H:%M:%S %Z')}")
                print(f"   User date: {user_today} ({user_today.strftime('%A')})")
                
                # Test week calculations
                week_start, week_end = get_week_dates(user_today, week_start_day=0)
                print(f"   Current week: {week_start} to {week_end}")
                
                # Test current week commits function
                try:
                    result = await get_current_week_github_commits(supabase, user_id, week_start_day=0)
                    if result:
                        print(f"   ✅ GitHub API Result:")
                        print(f"      Commits: {result['current_commits']}/{result['weekly_goal']}")
                        print(f"      Progress: {result.get('progress_percentage', 0):.1f}%")
                        print(f"      API Week: {result['week_start_date']} to {result['week_end_date']}")
                        
                        # Verify consistency
                        api_week_start = datetime.fromisoformat(result['week_start_date']).date()
                        if api_week_start == week_start:
                            print(f"      ✅ Week boundaries consistent with user timezone")
                        else:
                            print(f"      ❌ Week boundary mismatch! Local: {week_start}, API: {api_week_start}")
                    else:
                        print(f"   ⚠️  No GitHub data (token missing or no weekly habits)")
                except Exception as e:
                    print(f"   ❌ GitHub API Error: {e}")
                
            except Exception as e:
                print(f"   ❌ Error: {e}")
            
            print()  # Blank line between users
        
        # Test timezone boundary scenario
        await test_saturday_sunday_boundary()
        
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

async def test_saturday_sunday_boundary():
    """Test the specific Saturday→Sunday boundary issue."""
    
    print("🎯 Testing Saturday→Sunday Boundary Issue")
    print("-" * 42)
    
    # Simulate Saturday 11 PM Pacific = Sunday 7 AM UTC
    pacific_tz = pytz.timezone("America/Los_Angeles")
    saturday_night = pacific_tz.localize(datetime(2024, 1, 6, 23, 0))  # Sat 11 PM Pacific
    sunday_morning_utc = saturday_night.astimezone(pytz.UTC)  # Sun 7 AM UTC
    
    print(f"Scenario: Saturday night in Pacific timezone")
    print(f"User local time: {saturday_night.strftime('%A %Y-%m-%d %H:%M:%S %Z')}")
    print(f"Server UTC time: {sunday_morning_utc.strftime('%A %Y-%m-%d %H:%M:%S %Z')}")
    print()
    
    # Get dates
    user_date = saturday_night.date()
    server_date = sunday_morning_utc.date()
    
    print(f"User sees: {user_date} ({user_date.strftime('%A')})")
    print(f"Server sees: {server_date} ({server_date.strftime('%A')})")
    print()
    
    # Calculate week boundaries for both
    user_week_start, user_week_end = get_week_dates(user_date, week_start_day=0)
    server_week_start, server_week_end = get_week_dates(server_date, week_start_day=0)
    
    print(f"User timezone week:   {user_week_start} to {user_week_end}")
    print(f"Server timezone week: {server_week_start} to {server_week_end}")
    print()
    
    if user_week_start != server_week_start:
        print("✅ GOOD: Week boundaries are different")
        print("   → User still sees current week (includes Saturday)")
        print("   → System should use USER week, not server week")
        print("   → No premature reset!")
    else:
        print("❌ BAD: Week boundaries are the same") 
        print("   → Would cause premature reset")
    
    print()
    print("🎯 Key Point: GitHub habits should use USER timezone week boundaries")
    print("   This prevents resets when UTC crosses Sunday but user is still on Saturday")

async def run_quick_test():
    """Run the quick test."""
    
    print("GitHub Timezone Quick Test")
    print("🔍 Testing core functions with real data")
    print()
    
    await quick_test_github_functions()
    
    print("\n✅ Quick test complete!")
    print()
    print("📋 Summary:")
    print("   • get_user_timezone() - Retrieves and normalizes user timezones")
    print("   • get_week_dates() - Calculates week boundaries using user date")
    print("   • get_current_week_github_commits() - Uses user timezone for API calls")
    print("   • Saturday→Sunday boundary - Prevents premature resets")

if __name__ == "__main__":
    asyncio.run(run_quick_test()) 