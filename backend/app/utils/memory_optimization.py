import gc
import asyncio
from functools import wraps
from typing import Any, Callable, Optional, List
import weakref


def cleanup_memory(*objects):
    """Clean up memory by deleting objects and forcing garbage collection"""
    for obj in objects:
        if obj is not None:
            try:
                if hasattr(obj, 'clear') and callable(getattr(obj, 'clear')):
                    obj.clear()
                del obj
            except Exception:
                pass
    gc.collect()


def disable_print():
    """Return a no-op function to replace print statements"""
    def noop(*args, **kwargs):
        pass
    return noop


def memory_optimized(cleanup_args=True):
    """Decorator to automatically clean up function arguments after execution"""
    def decorator(func):
        @wraps(func)
        async def async_wrapper(*args, **kwargs):
            try:
                result = await func(*args, **kwargs)
                return result
            finally:
                if cleanup_args:
                    cleanup_memory(*args, *kwargs.values())
        
        @wraps(func)
        def sync_wrapper(*args, **kwargs):
            try:
                result = func(*args, **kwargs)
                return result
            finally:
                if cleanup_args:
                    cleanup_memory(*args, *kwargs.values())
        
        if asyncio.iscoroutinefunction(func):
            return async_wrapper
        else:
            return sync_wrapper
    return decorator


class MemoryLimitedList:
    """A list that automatically manages memory usage"""
    
    def __init__(self, max_size: int = 1000):
        self.max_size = max_size
        self._items = []
    
    def append(self, item):
        self._items.append(item)
        if len(self._items) > self.max_size:
            # Remove oldest items
            removed = self._items.pop(0)
            cleanup_memory(removed)
    
    def extend(self, items):
        for item in items:
            self.append(item)
    
    def clear(self):
        cleanup_memory(*self._items)
        self._items.clear()
    
    def __len__(self):
        return len(self._items)
    
    def __iter__(self):
        return iter(self._items)
    
    def __getitem__(self, index):
        return self._items[index]


class AsyncCoordinator:
    """Coordinate async operations with memory management"""
    
    def __init__(self, max_concurrent: int = 10):
        self.semaphore = asyncio.Semaphore(max_concurrent)
        self._active_tasks = weakref.WeakSet()
    
    async def execute(self, coro):
        """Execute a coroutine with coordination"""
        async with self.semaphore:
            task = asyncio.create_task(coro)
            self._active_tasks.add(task)
            try:
                result = await task
                return result
            finally:
                cleanup_memory(task)
    
    async def gather(self, *coroutines):
        """Execute multiple coroutines with coordination"""
        tasks = [self.execute(coro) for coro in coroutines]
        try:
            results = await asyncio.gather(*tasks)
            return results
        finally:
            cleanup_memory(*tasks)
    
    def cleanup(self):
        """Clean up the coordinator"""
        # Cancel any remaining tasks
        for task in list(self._active_tasks):
            if not task.done():
                task.cancel()
        cleanup_memory(self.semaphore)


async def batch_process(items: List[Any], processor: Callable, batch_size: int = 10):
    """Process items in batches with memory optimization"""
    coordinator = AsyncCoordinator(max_concurrent=batch_size)
    
    try:
        for i in range(0, len(items), batch_size):
            batch = items[i:i + batch_size]
            coroutines = [processor(item) for item in batch]
            
            results = await coordinator.gather(*coroutines)
            
            # Clean up batch immediately
            cleanup_memory(*batch, *coroutines)
            
            # Yield results
            for result in results:
                yield result
                
            # Clean up results
            cleanup_memory(*results)
    
    finally:
        coordinator.cleanup()
        cleanup_memory(coordinator) 