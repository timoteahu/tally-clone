import asyncio
from typing import Any, Coroutine, List, TypeVar, Callable, Dict, Optional
from utils.memory_optimization import AsyncCoordinator, cleanup_memory, memory_optimized
import logging

logger = logging.getLogger(__name__)
T = TypeVar('T')

# Global coordinator instances for different use cases
DEFAULT_COORDINATOR = AsyncCoordinator(max_concurrent=16)
HIGH_THROUGHPUT_COORDINATOR = AsyncCoordinator(max_concurrent=32)
LOW_MEMORY_COORDINATOR = AsyncCoordinator(max_concurrent=8)

async def fetch_with_coordination(
    fetch_functions: List[Callable[[], Coroutine[Any, Any, Any]]],
    max_concurrent: int = 16,
    return_exceptions: bool = True,
    cleanup_args: bool = True
) -> List[Any]:
    """
    Execute multiple fetch functions with bounded parallelism and automatic cleanup.
    
    Args:
        fetch_functions: List of async functions to execute
        max_concurrent: Maximum concurrent executions
        return_exceptions: Whether to return exceptions instead of raising
        cleanup_args: Whether to cleanup arguments after execution
        
    Returns:
        List of results from all fetch functions
        
    Example:
        results = await fetch_with_coordination([
            lambda: fetch_habits(supabase, user_id),
            lambda: fetch_friends(supabase, user_id),
            lambda: fetch_feed(supabase, user_id)
        ])
    """
    coordinator = AsyncCoordinator(max_concurrent=max_concurrent)
    
    try:
        # Create coroutines from functions
        coroutines = [func() for func in fetch_functions]
        
        # Execute with coordination
        if return_exceptions:
            # Handle exceptions manually since coordinator.gather doesn't support return_exceptions
            try:
                results = await coordinator.gather(*coroutines)
                return results
            except Exception as e:
                logger.error(f"Error in coordinated fetch: {e}")
                return [e] * len(fetch_functions)
        else:
            results = await coordinator.gather(*coroutines)
            return results
        
    except Exception as e:
        logger.error(f"Error in coordinated fetch: {e}")
        if return_exceptions:
            return [e] * len(fetch_functions)
        raise
    finally:
        if cleanup_args:
            cleanup_memory(fetch_functions, coroutines if 'coroutines' in locals() else None)

async def parallel_data_processing(
    data_items: List[Any],
    processor_func: Callable[[Any], Coroutine[Any, Any, T]],
    max_concurrent: int = 10,
    cleanup_batches: bool = True
) -> List[T]:
    """
    Process data items in parallel with memory-conscious batching.
    
    Args:
        data_items: List of items to process
        processor_func: Async function to process each item
        max_concurrent: Maximum concurrent processors
        cleanup_batches: Whether to cleanup after each batch
        
    Returns:
        List of processed results
        
    Example:
        processed_posts = await parallel_data_processing(
            raw_posts,
            lambda post: process_post(supabase, post),
            max_concurrent=10
        )
    """
    coordinator = AsyncCoordinator(max_concurrent=max_concurrent)
    
    try:
        # Create processing tasks
        tasks = [processor_func(item) for item in data_items]
        
        # Execute with coordination
        try:
            results = await coordinator.gather(*tasks)
            # Filter out None values
            successful_results = [r for r in results if r is not None]
            return successful_results
        except Exception as e:
            logger.error(f"Error in coordinated processing: {e}")
            return []
        
    except Exception as e:
        logger.error(f"Error in parallel data processing: {e}")
        return []
    finally:
        if cleanup_batches:
            cleanup_memory(data_items, tasks if 'tasks' in locals() else None, results if 'results' in locals() else None)

class DataFetcher:
    """
    A reusable class for coordinated data fetching with memory optimization.
    Use this for consistent data fetching patterns across your app.
    """
    
    def __init__(self, max_concurrent: int = 16):
        self.coordinator = AsyncCoordinator(max_concurrent=max_concurrent)
    
    @memory_optimized(cleanup_args=False)
    async def fetch_multiple(
        self,
        fetch_configs: Dict[str, Callable[[], Coroutine[Any, Any, Any]]]
    ) -> Dict[str, Any]:
        """
        Fetch multiple data sources and return as a named dictionary.
        
        Args:
            fetch_configs: Dict of {name: fetch_function} pairs
            
        Returns:
            Dict of {name: result} pairs
            
        Example:
            fetcher = DataFetcher()
            data = await fetcher.fetch_multiple({
                'habits': lambda: fetch_habits(supabase, user_id),
                'friends': lambda: fetch_friends(supabase, user_id),
                'feed': lambda: fetch_feed(supabase, user_id)
            })
            # Access as: data['habits'], data['friends'], etc.
        """
        try:
            # Create coroutines from functions
            coroutines = {name: func() for name, func in fetch_configs.items()}
            
            # Execute all fetches in parallel
            results = await self.coordinator.gather(*coroutines.values())
            
            # Map results back to names
            result_dict = {}
            for i, (name, _) in enumerate(fetch_configs.items()):
                result = results[i]
                if not isinstance(result, Exception):
                    result_dict[name] = result
                else:
                    logger.error(f"Error fetching {name}: {result}")
                    result_dict[name] = None
            
            return result_dict
            
        except Exception as e:
            logger.error(f"Error in DataFetcher.fetch_multiple: {e}")
            return {name: None for name in fetch_configs.keys()}

# Convenience functions for common patterns
async def fetch_user_data_bundle(
    supabase,
    user_id: str,
    fetch_functions: Dict[str, Callable[[], Coroutine[Any, Any, Any]]]
) -> Dict[str, Any]:
    """
    Fetch a complete bundle of user data with optimized coordination.
    
    Example:
        data = await fetch_user_data_bundle(supabase, user_id, {
            'habits': lambda: fetch_habits(supabase, user_id),
            'friends': lambda: fetch_friends(supabase, user_id),
            'feed': lambda: fetch_feed(supabase, user_id),
            'profile': lambda: fetch_user_profile(supabase, user_id)
        })
    """
    fetcher = DataFetcher(max_concurrent=16)
    return await fetcher.fetch_multiple(fetch_functions)

async def process_data_pipeline(
    initial_data: Any,
    pipeline_stages: List[Callable[[Any], Coroutine[Any, Any, Any]]],
    max_concurrent: int = 8
) -> Any:
    """
    Process data through a pipeline of async transformation stages.
    
    Args:
        initial_data: Starting data
        pipeline_stages: List of async transformation functions
        max_concurrent: Max concurrent operations per stage
        
    Returns:
        Final transformed data
    """
    current_data = initial_data
    
    try:
        for stage_func in pipeline_stages:
            current_data = await stage_func(current_data)
            
        return current_data
        
    except Exception as e:
        logger.error(f"Error in data pipeline: {e}")
        return None
    finally:
        cleanup_memory(initial_data, pipeline_stages) 