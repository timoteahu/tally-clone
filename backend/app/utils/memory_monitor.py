import psutil
import tracemalloc
import gc
import logging
from functools import wraps
from datetime import datetime
import asyncio

logger = logging.getLogger(__name__)

class MemoryMonitor:
    """Memory monitoring utility for tracking memory usage and potential leaks"""
    
    def __init__(self):
        self.start_memory = None
        self.peak_memory = 0
        
    def start_monitoring(self):
        """Start memory monitoring"""
        tracemalloc.start()
        process = psutil.Process()
        self.start_memory = process.memory_info().rss / 1024 / 1024  # MB
        logger.info(f"🔍 Memory monitoring started - Initial: {self.start_memory:.1f} MB")
        
    def get_current_memory(self):
        """Get current memory usage in MB"""
        process = psutil.Process()
        current = process.memory_info().rss / 1024 / 1024  # MB
        self.peak_memory = max(self.peak_memory, current)
        return current
        
    def log_memory_usage(self, context: str = ""):
        """Log current memory usage"""
        current = self.get_current_memory()
        if self.start_memory:
            diff = current - self.start_memory
            logger.info(f"📊 Memory {context}: {current:.1f} MB (+{diff:.1f} MB from start, peak: {self.peak_memory:.1f} MB)")
        else:
            logger.info(f"📊 Memory {context}: {current:.1f} MB")
            
    def force_garbage_collection(self):
        """Force garbage collection and log memory before/after"""
        before = self.get_current_memory()
        collected = gc.collect()
        after = self.get_current_memory()
        freed = before - after
        logger.info(f"🗑️ Garbage collection: {collected} objects collected, {freed:.1f} MB freed")
        
    def get_top_memory_consumers(self, limit=10):
        """Get top memory consuming traces"""
        if not tracemalloc.is_tracing():
            return "Memory tracing not started"
            
        snapshot = tracemalloc.take_snapshot()
        top_stats = snapshot.statistics('lineno')
        
        result = []
        for stat in top_stats[:limit]:
            size_mb = stat.size / 1024 / 1024
            result.append(f"{stat.traceback.format()[-1]}: {size_mb:.1f} MB")
        
        return "\n".join(result)

# Global memory monitor instance
memory_monitor = MemoryMonitor()

def monitor_memory(func_name: str = None):
    """Decorator to monitor memory usage of functions"""
    def decorator(func):
        @wraps(func)
        async def async_wrapper(*args, **kwargs):
            name = func_name or func.__name__
            before = memory_monitor.get_current_memory()
            
            try:
                result = await func(*args, **kwargs)
                after = memory_monitor.get_current_memory()
                diff = after - before
                
                if diff > 10:  # Log if function uses more than 10MB
                    logger.warning(f"⚠️ {name} used {diff:.1f} MB memory")
                elif diff > 5:  # Log if function uses more than 5MB
                    logger.info(f"📈 {name} used {diff:.1f} MB memory")
                    
                return result
            except Exception as e:
                after = memory_monitor.get_current_memory()
                diff = after - before
                logger.error(f"❌ {name} failed with {diff:.1f} MB memory usage: {e}")
                raise
                
        @wraps(func)
        def sync_wrapper(*args, **kwargs):
            name = func_name or func.__name__
            before = memory_monitor.get_current_memory()
            
            try:
                result = func(*args, **kwargs)
                after = memory_monitor.get_current_memory()
                diff = after - before
                
                if diff > 10:  # Log if function uses more than 10MB
                    logger.warning(f"⚠️ {name} used {diff:.1f} MB memory")
                elif diff > 5:  # Log if function uses more than 5MB
                    logger.info(f"📈 {name} used {diff:.1f} MB memory")
                    
                return result
            except Exception as e:
                after = memory_monitor.get_current_memory()
                diff = after - before
                logger.error(f"❌ {name} failed with {diff:.1f} MB memory usage: {e}")
                raise
                
        return async_wrapper if asyncio.iscoroutinefunction(func) else sync_wrapper
    return decorator

def log_system_memory():
    """Log system-wide memory statistics"""
    memory = psutil.virtual_memory()
    process = psutil.Process()
    
    logger.info(f"🖥️ System Memory - Total: {memory.total / 1024 / 1024 / 1024:.1f} GB, "
               f"Available: {memory.available / 1024 / 1024 / 1024:.1f} GB, "
               f"Used: {memory.percent:.1f}%")
    logger.info(f"🔧 Process Memory - RSS: {process.memory_info().rss / 1024 / 1024:.1f} MB, "
               f"VMS: {process.memory_info().vms / 1024 / 1024:.1f} MB")

# Automatic memory monitoring for critical endpoints
def setup_memory_monitoring():
    """Setup automatic memory monitoring"""
    memory_monitor.start_monitoring()
    
    # Schedule periodic memory checks (every 5 minutes)
    async def periodic_memory_check():
        while True:
            await asyncio.sleep(300)  # 5 minutes
            memory_monitor.log_memory_usage("periodic check")
            log_system_memory()
            
            # Force GC if memory is high
            current = memory_monitor.get_current_memory()
            if current > 400:  # If using more than 400MB
                memory_monitor.force_garbage_collection()
    
    # Start background task
    asyncio.create_task(periodic_memory_check()) 