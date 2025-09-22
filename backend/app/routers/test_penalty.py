from fastapi import APIRouter, Depends, HTTPException
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from routers.auth import get_current_user_lightweight
from models.schemas import User
from typing import List, Dict, Any

router = APIRouter()

@router.get("/test-penalty-amounts")
async def test_penalty_amounts(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Test endpoint to check if penalty amounts are working in get_user_feed function
    """
    try:
        user_id = str(current_user.id)
        
        print(f"🧪 Testing penalty amounts for user: {user_id}")
        
        # Call the get_user_feed function directly
        result = await supabase.rpc("get_user_feed", {"user_id_param": user_id}).execute()
        
        response_data = {
            "status": "success",
            "user_id": user_id,
            "posts_found": len(result.data) if result.data else 0,
            "posts": []
        }
        
        if result.data:
            for i, post in enumerate(result.data[:5]):  # Show first 5 posts
                post_info = {
                    "post_number": i + 1,
                    "post_id": post.get('post_id'),
                    "user_name": post.get('user_name'),
                    "habit_id": post.get('habit_id'),
                    "habit_name": post.get('habit_name'),
                    "habit_type": post.get('habit_type'),
                    "penalty_amount": post.get('penalty_amount'),
                    "penalty_amount_present": 'penalty_amount' in post,
                    "penalty_amount_value": post.get('penalty_amount', 'MISSING'),
                    "streak": post.get('streak'),
                    "all_fields": list(post.keys()) if isinstance(post, dict) else []
                }
                response_data["posts"].append(post_info)
                
                # Log to console for debugging
                print(f"📝 Post {i+1}:")
                print(f"   - User: {post.get('user_name')}")
                print(f"   - Habit: {post.get('habit_name')} ({post.get('habit_type')})")
                print(f"   - Penalty Amount: {post.get('penalty_amount')}")
                print(f"   - Available fields: {list(post.keys())}")
        else:
            print("📭 No posts found in feed")
            
            # Also check habits table directly
            habits_result = await supabase.table("habits").select("id, name, penalty_amount, user_id").gte("penalty_amount", 0.01).limit(5).execute()
            response_data["habits_with_penalties"] = habits_result.data if habits_result.data else []
            
            print(f"🎯 Found {len(habits_result.data)} habits with penalty amounts > 0")
        
        return response_data
        
    except Exception as e:
        print(f"❌ Error in test endpoint: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Test failed: {str(e)}")

@router.get("/test-function-schema")
async def test_function_schema(
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Test endpoint to check the schema of get_user_feed function
    """
    try:
        # Call with a dummy UUID to see the schema
        dummy_uuid = "00000000-0000-0000-0000-000000000000"
        result = await supabase.rpc("get_user_feed", {"user_id_param": dummy_uuid}).execute()
        
        response_data = {
            "status": "success",
            "function_exists": result.data is not None,
            "returned_empty_array": result.data == [],
            "sample_schema": []
        }
        
        if result.data is not None:
            if result.data and len(result.data) > 0:
                # We have actual data, show the schema
                sample_post = result.data[0]
                response_data["sample_schema"] = list(sample_post.keys())
                response_data["penalty_amount_present"] = 'penalty_amount' in sample_post
            else:
                # Empty array, but function exists - call with real user to get schema
                print("🔍 Function returns empty array for dummy UUID (expected)")
                
                # Get a real user to test schema
                users_result = await supabase.table("users").select("id").limit(1).execute()
                if users_result.data:
                    test_user_id = users_result.data[0]["id"]
                    real_result = await supabase.rpc("get_user_feed", {"user_id_param": test_user_id}).execute()
                    
                    if real_result.data and len(real_result.data) > 0:
                        sample_post = real_result.data[0]
                        response_data["sample_schema"] = list(sample_post.keys())
                        response_data["penalty_amount_present"] = 'penalty_amount' in sample_post
                    else:
                        response_data["sample_schema"] = "No posts available to determine schema"
        else:
            response_data["error"] = "Function call failed"
        
        return response_data
        
    except Exception as e:
        print(f"❌ Error checking function schema: {e}")
        raise HTTPException(status_code=500, detail=f"Schema test failed: {str(e)}") 