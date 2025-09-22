import httpx
import logging
from typing import Optional, Dict, Any
from datetime import datetime, date, timezone
import asyncio

logger = logging.getLogger(__name__)

class LeetCodeAPI:
    """Utility class for interacting with LeetCode's public API"""
    
    BASE_URL = "https://leetcode.com"
    GRAPHQL_URL = f"{BASE_URL}/graphql"
    
    @staticmethod
    async def check_profile_public(username: str) -> Dict[str, Any]:
        """
        Check if a LeetCode user's profile is public.
        
        Returns:
            dict: {
                "exists": bool,
                "is_public": bool,
                "message": str,
                "profile_data": dict (if public)
            }
        """
        query = """
        query getUserProfile($username: String!) {
            matchedUser(username: $username) {
                username
                profile {
                    realName
                    userSlug
                    reputation
                    ranking
                }
                submitStats {
                    acSubmissionNum {
                        difficulty
                        count
                        submissions
                    }
                    totalSubmissionNum {
                        difficulty
                        count
                        submissions
                    }
                }
            }
        }
        """
        
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    LeetCodeAPI.GRAPHQL_URL,
                    json={
                        "query": query,
                        "variables": {"username": username}
                    },
                    headers={
                        "Content-Type": "application/json",
                        "Referer": LeetCodeAPI.BASE_URL
                    }
                )
                
                if response.status_code != 200:
                    logger.error(f"LeetCode API error: {response.status_code}")
                    return {
                        "exists": False,
                        "is_public": False,
                        "message": "Failed to connect to LeetCode API"
                    }
                
                data = response.json()
                
                # Check if user exists
                if not data.get("data", {}).get("matchedUser"):
                    return {
                        "exists": False,
                        "is_public": False,
                        "message": f"User '{username}' not found on LeetCode"
                    }
                
                user_data = data["data"]["matchedUser"]
                
                # Check if we can access their stats (indicator of public profile)
                if user_data.get("submitStats") and user_data["submitStats"].get("acSubmissionNum"):
                    return {
                        "exists": True,
                        "is_public": True,
                        "message": "Profile is public",
                        "profile_data": user_data
                    }
                else:
                    return {
                        "exists": True,
                        "is_public": False,
                        "message": "Profile exists but is private. Please make your LeetCode profile public in your account settings."
                    }
                    
        except Exception as e:
            logger.error(f"Error checking LeetCode profile: {e}")
            return {
                "exists": False,
                "is_public": False,
                "message": f"Error checking profile: {str(e)}"
            }
    
    @staticmethod
    async def get_user_stats(username: str) -> Optional[Dict[str, Any]]:
        """
        Get user statistics from LeetCode.
        
        Returns:
            dict: User statistics including solved problems, or None if error
        """
        query = """
        query getUserStats($username: String!) {
            matchedUser(username: $username) {
                username
                submitStats {
                    acSubmissionNum {
                        difficulty
                        count
                        submissions
                    }
                }
                profile {
                    ranking
                    reputation
                }
            }
        }
        """
        
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    LeetCodeAPI.GRAPHQL_URL,
                    json={
                        "query": query,
                        "variables": {"username": username}
                    },
                    headers={
                        "Content-Type": "application/json",
                        "Referer": LeetCodeAPI.BASE_URL
                    }
                )
                
                if response.status_code != 200:
                    return None
                
                data = response.json()
                return data.get("data", {}).get("matchedUser")
                
        except Exception as e:
            logger.error(f"Error getting LeetCode stats: {e}")
            return None
    
    @staticmethod
    async def get_daily_submissions(username: str, target_date: date) -> int:
        """
        Get the number of submissions for a specific date using the submission calendar.
        
        IMPORTANT: This returns TOTAL submission attempts (including failed ones),
        not the number of unique problems solved or accepted submissions.
        
        Args:
            username: LeetCode username
            target_date: Date to check submissions for
            
        Returns:
            Number of total submission attempts on the target date
        """
        try:
            # Get the year for the calendar query
            year = target_date.year
            
            # Query for user calendar data
            query = """
            query getUserCalendar($username: String!, $year: Int!) {
                matchedUser(username: $username) {
                    userCalendar(year: $year) {
                        submissionCalendar
                    }
                }
            }
            """
            
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    LeetCodeAPI.GRAPHQL_URL,
                    json={
                        "query": query,
                        "variables": {"username": username, "year": year}
                    },
                    headers={
                        "Content-Type": "application/json",
                        "Referer": LeetCodeAPI.BASE_URL
                    }
                )
                
                if response.status_code != 200:
                    logger.error(f"Failed to get calendar data: HTTP {response.status_code}")
                    return 0
                
                data = response.json()
                
                # Extract submission calendar
                user_data = data.get("data", {}).get("matchedUser")
                if not user_data:
                    logger.error(f"User {username} not found")
                    return 0
                
                calendar_data = user_data.get("userCalendar", {}).get("submissionCalendar")
                if not calendar_data:
                    return 0
                
                # Parse the JSON calendar data
                import json
                calendar_dict = json.loads(calendar_data)
                
                # Convert target date to Unix timestamp (start of day in UTC)
                from datetime import datetime, timezone
                target_datetime = datetime.combine(target_date, datetime.min.time())
                target_timestamp = int(target_datetime.replace(tzinfo=timezone.utc).timestamp())
                
                # Get submissions for the target date
                submissions = calendar_dict.get(str(target_timestamp), 0)
                
                logger.info(f"User {username} had {submissions} submissions on {target_date}")
                return submissions
                
        except Exception as e:
            logger.error(f"Error getting daily submissions: {e}")
            return 0
    
    @staticmethod
    async def get_daily_problems_solved(username: str, target_date: date) -> int:
        """
        Get the number of unique problems solved (accepted) on a specific date.
        
        This is what should be used for habit tracking, as it counts actual
        problem completions, not submission attempts.
        
        Args:
            username: LeetCode username
            target_date: Date to check problems solved
            
        Returns:
            Number of unique problems solved on the target date
        """
        try:
            # Get recent accepted submissions
            query = """
            query getRecentAcSubmissions($username: String!, $limit: Int!) {
                recentAcSubmissionList(username: $username, limit: $limit) {
                    id
                    title
                    titleSlug
                    timestamp
                }
            }
            """
            
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    LeetCodeAPI.GRAPHQL_URL,
                    json={
                        "query": query,
                        "variables": {"username": username, "limit": 200}  # Get more to ensure we cover the date
                    },
                    headers={
                        "Content-Type": "application/json",
                        "Referer": LeetCodeAPI.BASE_URL
                    }
                )
                
                if response.status_code != 200:
                    logger.error(f"Failed to get AC submissions: HTTP {response.status_code}")
                    return 0
                
                data = response.json()
                submissions = data.get("data", {}).get("recentAcSubmissionList", [])
                
                # Count unique problems solved on target date
                problems_solved = set()
                
                for sub in submissions:
                    timestamp = int(sub.get("timestamp", 0))
                    submit_date = datetime.fromtimestamp(timestamp, tz=timezone.utc).date()
                    
                    if submit_date == target_date:
                        problem_slug = sub.get("titleSlug", "")
                        if problem_slug:
                            problems_solved.add(problem_slug)
                    elif submit_date < target_date:
                        # Submissions are in reverse chronological order
                        break
                
                count = len(problems_solved)
                logger.info(f"User {username} solved {count} unique problems on {target_date}")
                return count
                
        except Exception as e:
            logger.error(f"Error getting daily problems solved: {e}")
            return 0
    
    @staticmethod
    async def get_recent_submissions(username: str, limit: int = 20) -> Optional[Dict[str, Any]]:
        """
        Get recent submissions for a user.
        
        Returns:
            dict: Recent submission data or None if error
        """
        query = """
        query getRecentSubmissions($username: String!, $limit: Int!) {
            recentSubmissionList(username: $username, limit: $limit) {
                title
                titleSlug
                timestamp
                statusDisplay
                lang
            }
        }
        """
        
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    LeetCodeAPI.GRAPHQL_URL,
                    json={
                        "query": query,
                        "variables": {"username": username, "limit": limit}
                    },
                    headers={
                        "Content-Type": "application/json",
                        "Referer": LeetCodeAPI.BASE_URL
                    }
                )
                
                if response.status_code != 200:
                    return None
                
                data = response.json()
                return data.get("data", {}).get("recentSubmissionList")
                
        except Exception as e:
            logger.error(f"Error getting recent submissions: {e}")
            return None