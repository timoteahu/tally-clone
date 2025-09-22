#!/usr/bin/env python3
"""Quick manual test count how many commits the authenticated user made yesterday.

Usage:
    GITHUB_TOKEN=ghp_xxx python test_github_commits.py
"""
import asyncio, datetime, httpx, pytz, os
from datetime import time

# ---------------------------------------------------------------
# SECURITY: GitHub token must be provided via environment variable
# Do NOT commit real PATs to version control in production code.
# ---------------------------------------------------------------

GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")  # Use environment variable instead

async def get_yesterday_commit_count(timezone_str='UTC'):
    """Get commit count for yesterday in the specified timezone."""
    # Get user's timezone
    user_tz = pytz.timezone(timezone_str)
    
    # Get yesterday's date in user's timezone  
    user_now = datetime.datetime.now(user_tz)
    yesterday_date = user_now.date() - datetime.timedelta(days=1)
    
    # Create timezone-aware datetime objects for start and end of yesterday
    start_local = user_tz.localize(datetime.datetime.combine(yesterday_date, time.min))
    end_local = user_tz.localize(datetime.datetime.combine(yesterday_date, time.max))
    
    # Convert to UTC for GitHub API (GitHub expects UTC timestamps)
    start_utc = start_local.astimezone(pytz.UTC).replace(tzinfo=None)
    end_utc = end_local.astimezone(pytz.UTC).replace(tzinfo=None)
    
    start = start_utc.isoformat() + "Z"
    end = end_utc.isoformat() + "Z"

    query = {
        "query": f"""
        query {{
          viewer {{
            contributionsCollection(from: \"{start}\", to: \"{end}\") {{
              commitContributionsByRepository {{
                repository {{ nameWithOwner }}
                contributions {{ totalCount }}
              }}
              totalCommitContributions
            }}
          }}
        }}
        """
    }

    headers = {"Authorization": f"Bearer {GITHUB_TOKEN}"}
    async with httpx.AsyncClient() as client:
        resp = await client.post("https://api.github.com/graphql", json=query, headers=headers, timeout=20)
        if resp.status_code != 200:
            print("GitHub API error", resp.status_code, resp.text)
            return None
        data = resp.json()
        count = data["data"]["viewer"]["contributionsCollection"]["totalCommitContributions"]
        return count, yesterday_date, timezone_str

if __name__ == "__main__":
    # Test with different timezones
    test_timezones = ['UTC', 'America/Los_Angeles', 'America/New_York', 'America/Chicago']
    
    for tz in test_timezones:
        try:
            result = asyncio.run(get_yesterday_commit_count(tz))
            if result is not None:
                count, date, timezone = result
                print(f"✅ {timezone}: You made {count} commit(s) on {date} (yesterday)")
            else:
                print(f"❌ {tz}: Failed to get commit count")
        except Exception as e:
            print(f"❌ {tz}: Error - {e}")
    
    # Also test with default UTC
    print("\n--- Default UTC test ---")
    result = asyncio.run(get_yesterday_commit_count())
    if result is not None:
        count, date, timezone = result
        print(f"✅ You made {count} commit(s) on {date} (yesterday in {timezone})")
    else:
        print("❌ Failed to get commit count") 