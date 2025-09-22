from datetime import datetime, timedelta, timezone
from typing import List, Dict, Optional
from uuid import UUID
import logging
import json

from services.riot_api_service import RiotAPIService
from models.schemas import GamingSession, GamingVerificationResult
from config.database import get_supabase_client
from utils.weekly_habits import get_week_dates

logger = logging.getLogger(__name__)

class GamingHabitService:
    def __init__(self):
        self.riot_api = RiotAPIService()
        self.supabase = get_supabase_client()
    
    async def link_riot_account(self, user_id: str, riot_id: str, tagline: str, region: str, game_name: str) -> Dict:
        """Link a Riot account to a user."""
        try:
            logger.info(f"Starting link_riot_account for user {user_id}")
            
            # Get PUUID from Riot API
            puuid = await self.riot_api.get_puuid_by_riot_id(riot_id, tagline, region)
            logger.info(f"Got PUUID: {puuid}")
            
            if not puuid:
                return {"success": False, "error": "Riot account not found"}
            
            # Test the connection by fetching recent matches
            logger.info("Testing connection by fetching recent matches...")
            test_date = datetime.now(timezone.utc) - timedelta(days=1)
            
            # Try to fetch matches for the specified game to verify the account works
            try:
                if game_name == "lol" or game_name == "both":
                    try:
                        test_matches = await self.riot_api.get_lol_matches_for_date(puuid, region, test_date)
                        logger.info(f"Found {len(test_matches)} LoL matches for testing")
                    except (ValueError, KeyError) as lol_error:
                        logger.info(f"No LoL matches found or error: {lol_error}")
                        if game_name == "lol":
                            return {"success": False, "error": "Could not verify League of Legends account. Make sure you've played recently."}
                
                if game_name == "valorant" or game_name == "both":
                    try:
                        test_matches = await self.riot_api.get_valorant_matches_for_date(puuid, region, test_date)
                        logger.info(f"Found {len(test_matches)} Valorant matches for testing")
                    except (ValueError, KeyError) as val_error:
                        logger.info(f"No Valorant matches found or error: {val_error}")
                        if "403" in str(val_error) or "Forbidden" in str(val_error):
                            error_msg = "Valorant API requires a production key. Currently only League of Legends tracking is available."
                        else:
                            error_msg = "Could not verify Valorant account. Make sure you've played recently."
                        
                        if game_name == "valorant":
                            return {"success": False, "error": error_msg}
                            
                # For "both", we don't fail if one game has no matches - they might only play one
                if game_name == "both":
                    logger.info("Account verified for Riot Games (may play only one game)")
                    
            except (ValueError, KeyError, ConnectionError, TimeoutError) as e:
                logger.error(f"Failed to fetch test matches: {e}")
                return {"success": False, "error": "Could not verify Riot account. Please check your Riot ID and region."}
            
            # Check if account already exists for this user (same PUUID = same account)
            logger.info("Checking for existing account...")
            existing = self.supabase.table("riot_accounts").select("*").eq("user_id", user_id).eq("puuid", puuid).execute()
            if existing.data:
                # Update the existing account to support the new game if needed
                account_id = existing.data[0]["id"]
                current_game = existing.data[0]["game_name"]
                
                # If it's already set to this game or "both", no need to update
                if current_game == game_name or current_game == "both":
                    return {"success": True, "account": existing.data[0]}
                
                # Update to "both" if it's a different game
                # If trying to add "both" when we already have a specific game, update to "both"
                if game_name == "both" and current_game in ["lol", "valorant"]:
                    update_data = {"game_name": "both", "updated_at": datetime.now(timezone.utc).isoformat()}
                else:
                    update_data = {"game_name": "both", "updated_at": datetime.now(timezone.utc).isoformat()}
                update_result = self.supabase.table("riot_accounts").update(update_data).eq("id", account_id).execute()
                
                if update_result.data:
                    return {"success": True, "account": update_result.data[0]}
                else:
                    return {"success": False, "error": "Failed to update account"}
            
            # Check if someone else has linked this PUUID
            other_user = self.supabase.table("riot_accounts").select("*").eq("puuid", puuid).neq("user_id", user_id).execute()
            if other_user.data:
                return {"success": False, "error": "This Riot account is already linked to another user"}
            
            # Insert riot account
            account_data = {
                "user_id": user_id,
                "riot_id": riot_id,
                "tagline": tagline,
                "puuid": puuid,
                "region": region,
                "game_name": game_name
            }
            
            logger.info(f"Inserting account data: {account_data}")
            result = self.supabase.table("riot_accounts").insert(account_data).execute()
            logger.info(f"Insert result type: {type(result)}")
            logger.info(f"Insert result.data type: {type(result.data)}")
            
            if result.data:
                logger.info(f"Result data[0] type: {type(result.data[0])}")
                logger.info(f"Result data[0] keys: {result.data[0].keys() if hasattr(result.data[0], 'keys') else 'No keys method'}")
                
                # Try to print the actual data
                try:
                    import json
                    logger.info(f"Result data[0] as JSON: {json.dumps(result.data[0], default=str)}")
                except (ValueError, json.JSONDecodeError) as je:
                    logger.error(f"JSON serialization error: {je}")
                    logger.info(f"Result data[0] repr: {repr(result.data[0])}")
                
                # Manually construct the response to avoid serialization issues
                account_response = {
                    "id": str(result.data[0].get("id")) if result.data[0].get("id") else None,
                    "user_id": user_id,
                    "riot_id": riot_id,
                    "tagline": tagline,
                    "puuid": puuid,
                    "region": region,
                    "game_name": game_name,
                    "last_sync_at": str(result.data[0].get("last_sync_at")) if result.data[0].get("last_sync_at") else None,
                    "created_at": str(result.data[0].get("created_at")) if result.data[0].get("created_at") else None,
                    "updated_at": str(result.data[0].get("updated_at")) if result.data[0].get("updated_at") else None
                }
                logger.info("Successfully constructed account_response")
                return {"success": True, "account": account_response}
            else:
                return {"success": False, "error": "Failed to link account"}
                
        except (ValueError, KeyError, ConnectionError, TimeoutError) as e:
            logger.error(f"Error linking Riot account: {str(e)}")
            logger.error(f"Error type: {type(e)}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            return {"success": False, "error": str(e)}
        except Exception as e:
            logger.exception(f"Unexpected error linking Riot account: {e}")
            return {"success": False, "error": "Unexpected error occurred"}
    
    async def get_user_riot_accounts(self, user_id: str) -> List[Dict]:
        """Get all Riot accounts linked to a user."""
        try:
            result = self.supabase.table("riot_accounts").select("*").eq("user_id", user_id).execute()
            return result.data if result.data is not None else []
        except (ValueError, KeyError, ConnectionError, TimeoutError) as e:
            logger.error(f"Error fetching Riot accounts: {str(e)}")
            return []
        except Exception as e:
            logger.exception(f"Unexpected error fetching Riot accounts: {e}")
            return []
    
    async def verify_gaming_habit(self, habit_id: str, user_id: str, target_date: datetime) -> GamingVerificationResult:
        """Verify gaming time for a habit on the target date."""
        try:
            # Get habit details
            habit_result = self.supabase.table("habits").select("*").eq("id", habit_id).eq("user_id", user_id).single().execute()
            if not habit_result.data:
                raise ValueError("Habit not found")
            
            habit = habit_result.data
            games_tracked = habit.get("games_tracked", [])
            daily_limit_hours = habit.get("daily_limit_hours", 0)
            hourly_penalty_rate = habit.get("hourly_penalty_rate", 0)
            
            # Get user's Riot accounts for the tracked games
            riot_accounts = await self.get_user_riot_accounts(user_id)
            relevant_accounts = []
            for acc in riot_accounts:
                game_name = acc.get("game_name")
                # Include account if it matches the tracked game or if it's "both" and we're tracking either game
                if game_name in games_tracked or (game_name == "both" and any(g in ["lol", "valorant"] for g in games_tracked)):
                    relevant_accounts.append(acc)
            
            if not relevant_accounts:
                return GamingVerificationResult(
                    total_minutes_yesterday=0,
                    daily_limit_hours=daily_limit_hours,
                    overage_hours=0,
                    penalty_amount=0,
                    matches_counted=0,
                    sessions=[]
                )
            
            # Collect all gaming sessions for the target date
            all_sessions = []
            total_minutes = 0
            
            for account in relevant_accounts:
                puuid = account.get("puuid")
                region = account.get("region")
                game_name = account.get("game_name")
                
                if not puuid:
                    continue
                
                # Fetch matches based on which games are being tracked
                # If account supports "both" games, check which games this habit is tracking
                if (game_name == "lol" or game_name == "both") and "lol" in games_tracked:
                    matches = await self.riot_api.get_lol_matches_for_date(puuid, region, target_date)
                    
                    for match in matches:
                        match_id = match.get("metadata", {}).get("matchId")
                        
                        # Check if we already tracked this match
                        existing = self.supabase.table("gaming_sessions").select("id").eq("habit_id", habit_id).eq("match_id", match_id).execute()
                        if existing.data:
                            continue
                        
                        # Calculate duration
                        start_time, end_time, duration_minutes = self.riot_api.calculate_lol_match_duration(match)
                        queue_id = match.get("info", {}).get("queueId", 0)
                        game_mode = self.riot_api.get_lol_queue_type(queue_id)
                        
                        session_data = {
                            "habit_id": habit_id,
                            "match_id": match_id,
                            "game_start_time": start_time.isoformat(),
                            "game_end_time": end_time.isoformat(),
                            "duration_minutes": duration_minutes,
                            "game_mode": game_mode
                        }
                        
                        # Insert session
                        session_result = self.supabase.table("gaming_sessions").insert(session_data).execute()
                        if session_result.data:
                            all_sessions.append(GamingSession(**session_result.data[0]))
                            total_minutes += duration_minutes
                            
                if (game_name == "valorant" or game_name == "both") and "valorant" in games_tracked:
                    matches = await self.riot_api.get_valorant_matches_for_date(puuid, region, target_date)
                    
                    for match in matches:
                        match_id = match.get("matchInfo", {}).get("matchId")
                        
                        # Check if we already tracked this match
                        existing = self.supabase.table("gaming_sessions").select("id").eq("habit_id", habit_id).eq("match_id", match_id).execute()
                        if existing.data:
                            continue
                        
                        # Calculate duration
                        start_time, end_time, duration_minutes = self.riot_api.calculate_valorant_match_duration(match)
                        game_mode = self.riot_api.get_valorant_game_mode(match)
                        
                        session_data = {
                            "habit_id": habit_id,
                            "match_id": match_id,
                            "game_start_time": start_time.isoformat(),
                            "game_end_time": end_time.isoformat(),
                            "duration_minutes": duration_minutes,
                            "game_mode": game_mode
                        }
                        
                        # Insert session
                        session_result = self.supabase.table("gaming_sessions").insert(session_data).execute()
                        if session_result.data:
                            all_sessions.append(GamingSession(**session_result.data[0]))
                            total_minutes += duration_minutes
            
            # Calculate overage and penalty
            total_hours = total_minutes / 60
            overage_hours = max(0, total_hours - daily_limit_hours)
            penalty_amount = overage_hours * hourly_penalty_rate
            
            # Update last sync time for accounts
            for account in relevant_accounts:
                self.supabase.table("riot_accounts").update({
                    "last_sync_at": datetime.now(timezone.utc).isoformat()
                }).eq("id", account["id"]).execute()
            
            return GamingVerificationResult(
                total_minutes_yesterday=total_minutes,
                daily_limit_hours=daily_limit_hours,
                overage_hours=overage_hours,
                penalty_amount=penalty_amount,
                matches_counted=len(all_sessions),
                sessions=all_sessions
            )
            
        except (ValueError, KeyError, ConnectionError, TimeoutError) as e:
            logger.error(f"Error verifying gaming habit: {str(e)}")
            raise
        except Exception as e:
            logger.exception(f"Unexpected error verifying gaming habit: {e}")
            raise
    
    async def get_gaming_sessions(self, habit_id: str, start_date: Optional[datetime] = None, end_date: Optional[datetime] = None) -> List[GamingSession]:
        """Get gaming sessions for a habit within a date range."""
        try:
            # Always fetch from Riot API first if we have a date range
            if start_date and end_date:
                logger.info(f"Fetching from Riot API for habit {habit_id} for dates {start_date} to {end_date}")
                
                # Get habit details to know which user and games to fetch
                habit_result = self.supabase.table("habits").select("*").eq("id", habit_id).single().execute()
                if not habit_result.data:
                    logger.error(f"Habit {habit_id} not found")
                    return []
                
                habit = habit_result.data
                user_id = habit.get("user_id")
                games_tracked = habit.get("games_tracked", [])
                
                # Get user's Riot accounts
                riot_accounts = await self.get_user_riot_accounts(user_id)
                relevant_accounts = []
                for acc in riot_accounts:
                    game_name = acc.get("game_name")
                    if game_name in games_tracked or (game_name == "both" and any(g in ["lol", "valorant"] for g in games_tracked)):
                        relevant_accounts.append(acc)
                
                if not relevant_accounts:
                    logger.info(f"No relevant Riot accounts found for habit {habit_id}")
                    return []
                
                # Get user's timezone to properly handle date ranges
                user_tz_result = self.supabase.table("users").select("timezone").eq("id", user_id).single().execute()
                user_timezone = user_tz_result.data.get("timezone", "America/Los_Angeles") if user_tz_result.data else "America/Los_Angeles"
                logger.info(f"User timezone: {user_timezone}")
                
                # Initialize sessions list to collect new sessions
                sessions = []
                
                # Fetch sessions for each day in the range
                current_date = start_date
                while current_date < end_date:
                    logger.info(f"Fetching sessions for date: {current_date.date()}")
                    logger.info(f"Current date full: {current_date}")
                    logger.info(f"Current date timezone: {current_date.tzinfo}")
                    
                    for account in relevant_accounts:
                        puuid = account.get("puuid")
                        region = account.get("region")
                        game_name = account.get("game_name")
                        riot_id = account.get("riot_id")
                        tagline = account.get("tagline")
                        
                        logger.info(f"Processing account: {riot_id}#{tagline} (PUUID: {puuid})")
                        
                        if not puuid:
                            logger.warning(f"No PUUID for account {riot_id}#{tagline}")
                            continue
                        
                        # Fetch matches based on which games are being tracked
                        if (game_name == "lol" or game_name == "both") and "lol" in games_tracked:
                            logger.info(f"Fetching LoL matches for {riot_id}#{tagline} (PUUID {puuid}) on {current_date.date()}")
                            matches = await self.riot_api.get_lol_matches_for_date(puuid, region, current_date)
                            logger.info(f"Found {len(matches)} LoL matches")
                            
                            for match in matches:
                                match_id = match.get("metadata", {}).get("matchId")
                                
                                # Check if we already tracked this match
                                existing = self.supabase.table("gaming_sessions").select("id").eq("habit_id", habit_id).eq("match_id", match_id).execute()
                                if existing.data:
                                    continue
                                
                                # Calculate duration
                                start_time, end_time, duration_minutes = self.riot_api.calculate_lol_match_duration(match)
                                
                                # Check if this match actually belongs to the current date we're processing
                                # Use the game start time to determine which day it belongs to
                                match_date = start_time.date()
                                current_date_only = current_date.date()
                                
                                # Only include matches that actually started on the target date
                                if match_date != current_date_only:
                                    logger.info(f"Skipping match {match_id} - started on {match_date}, looking for {current_date_only}")
                                    continue
                                
                                queue_id = match.get("info", {}).get("queueId", 0)
                                game_mode = self.riot_api.get_lol_queue_type(queue_id)
                                
                                session_data = {
                                    "habit_id": habit_id,
                                    "match_id": match_id,
                                    "game_start_time": start_time.isoformat(),
                                    "game_end_time": end_time.isoformat(),
                                    "duration_minutes": duration_minutes,
                                    "game_mode": game_mode
                                }
                                
                                # Insert session
                                session_result = self.supabase.table("gaming_sessions").insert(session_data).execute()
                                if session_result.data:
                                    sessions.append(GamingSession(**session_result.data[0]))
                        
                        if (game_name == "valorant" or game_name == "both") and "valorant" in games_tracked:
                            logger.info(f"Fetching Valorant matches for PUUID {puuid} on {current_date.date()}")
                            try:
                                matches = await self.riot_api.get_valorant_matches_for_date(puuid, region, current_date)
                                logger.info(f"Found {len(matches)} Valorant matches")
                                
                                for match in matches:
                                    match_id = match.get("matchInfo", {}).get("matchId")
                                    
                                    # Check if we already tracked this match
                                    existing = self.supabase.table("gaming_sessions").select("id").eq("habit_id", habit_id).eq("match_id", match_id).execute()
                                    if existing.data:
                                        continue
                                    
                                    # Calculate duration
                                    start_time, end_time, duration_minutes = self.riot_api.calculate_valorant_match_duration(match)
                                    game_mode = self.riot_api.get_valorant_game_mode(match)
                                    
                                    session_data = {
                                        "habit_id": habit_id,
                                        "match_id": match_id,
                                        "game_start_time": start_time.isoformat(),
                                        "game_end_time": end_time.isoformat(),
                                        "duration_minutes": duration_minutes,
                                        "game_mode": game_mode
                                    }
                                    
                                    # Insert session
                                    session_result = self.supabase.table("gaming_sessions").insert(session_data).execute()
                                    if session_result.data:
                                        sessions.append(GamingSession(**session_result.data[0]))
                            except (ValueError, KeyError) as val_error:
                                logger.warning(f"Error fetching Valorant matches: {val_error}")
                                if "403" in str(val_error) or "Forbidden" in str(val_error):
                                    logger.info("Valorant API requires production key, skipping")
                    
                    # Move to next day
                    current_date += timedelta(days=1)
                
                # Update last sync time for accounts
                for account in relevant_accounts:
                    self.supabase.table("riot_accounts").update({
                        "last_sync_at": datetime.now(timezone.utc).isoformat()
                    }).eq("id", account["id"]).execute()
            
            # Now fetch all sessions from DB (including the ones we just added)
            query = self.supabase.table("gaming_sessions").select("*").eq("habit_id", habit_id)
            
            if start_date:
                query = query.gte("game_start_time", start_date.isoformat())
            if end_date:
                query = query.lte("game_start_time", end_date.isoformat())
            
            query = query.order("game_start_time", desc=True)
            
            result = query.execute()
            sessions = [GamingSession(**session) for session in result.data]
            
            return sessions
            
        except (ValueError, KeyError, ConnectionError, TimeoutError) as e:
            logger.error(f"Error fetching gaming sessions: {str(e)}")
            return []
        except Exception as e:
            logger.exception(f"Unexpected error fetching gaming sessions: {e}")
            return []
    
    async def calculate_weekly_gaming_total(self, habit_id: str, week_start: datetime) -> Dict:
        """Calculate total gaming time for a weekly habit."""
        try:
            week_end = week_start + timedelta(days=7)
            
            # Get all sessions for the week
            sessions = await self.get_gaming_sessions(habit_id, week_start, week_end)
            
            total_minutes = sum(session.duration_minutes for session in sessions)
            total_hours = total_minutes / 60
            
            # Get habit details for limit
            habit_result = self.supabase.table("habits").select("daily_limit_hours, hourly_penalty_rate").eq("id", habit_id).single().execute()
            habit = habit_result.data
            
            # For weekly habits, daily_limit_hours is actually the weekly limit
            weekly_limit_hours = habit.get("daily_limit_hours", 0) 
            hourly_penalty_rate = habit.get("hourly_penalty_rate", 0)
            
            overage_hours = max(0, total_hours - weekly_limit_hours)
            penalty_amount = overage_hours * hourly_penalty_rate
            
            return {
                "total_minutes": total_minutes,
                "total_hours": total_hours,
                "weekly_limit_hours": weekly_limit_hours,
                "overage_hours": overage_hours,
                "penalty_amount": penalty_amount,
                "sessions_count": len(sessions)
            }
            
        except (ValueError, KeyError, ConnectionError, TimeoutError) as e:
            logger.error(f"Error calculating weekly gaming total: {str(e)}")
            raise
        except Exception as e:
            logger.exception(f"Unexpected error calculating weekly gaming total: {e}")
            raise