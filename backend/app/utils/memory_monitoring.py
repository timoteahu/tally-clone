import time
import functools
import asyncio
from typing import Optional, Dict, Any, Callable
from utils.memory_optimization import cleanup_memory, disable_print

# Disable verbose printing for performance
print = disable_print()

try:
    import psutil
    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False
    print("⚠️ psutil not available - memory monitoring will be limited")

class MemoryMonitor:
    """
    Advanced memory monitoring for verification operations.
    Tracks memory usage, peaks, and identifies memory leaks.
    """
    
    def __init__(self, operation_name: str = "unknown"):
        self.operation_name = operation_name
        self.start_memory = 0
        self.peak_memory = 0
        self.current_memory = 0
        self.measurements = []
        self.start_time = time.time()
        
    def __enter__(self):
        self.start_memory = self.get_memory_usage()
        self.peak_memory = self.start_memory
        print(f"📊 [{self.operation_name}] Starting - Memory: {self.start_memory:.1f} MB")
        return self
        
    def __exit__(self, exc_type, exc_val, exc_tb):
        final_memory = self.get_memory_usage()
        duration = time.time() - self.start_time
        memory_diff = final_memory - self.start_memory
        
        print(f"📊 [{self.operation_name}] Complete:")
        print(f"  • Duration: {duration:.2f}s")
        print(f"  • Start: {self.start_memory:.1f} MB")
        print(f"  • Peak: {self.peak_memory:.1f} MB")
        print(f"  • Final: {final_memory:.1f} MB")
        print(f"  • Change: {memory_diff:+.1f} MB")
        
        if memory_diff > 10:
            print(f"⚠️ [{self.operation_name}] Possible memory leak: {memory_diff:.1f} MB increase")
        elif memory_diff > 0:
            print(f"📈 [{self.operation_name}] Memory increase: {memory_diff:.1f} MB")
        else:
            print(f"✅ [{self.operation_name}] Memory optimized: {memory_diff:.1f} MB")
    
    def checkpoint(self, checkpoint_name: str) -> float:
        """Record a memory checkpoint during operation"""
        current = self.get_memory_usage()
        self.peak_memory = max(self.peak_memory, current)
        
        # Calculate change since last measurement
        if self.measurements:
            last_memory = self.measurements[-1]['memory']
            change = current - last_memory
            change_str = f"{change:+.1f} MB"
        else:
            change_str = "baseline"
        
        self.measurements.append({
            'name': checkpoint_name,
            'memory': current,
            'time': time.time() - self.start_time
        })
        
        print(f"📊 [{self.operation_name}] {checkpoint_name}: {current:.1f} MB ({change_str})")
        return current
    
    def get_memory_usage(self) -> float:
        """Get current memory usage in MB"""
        if PSUTIL_AVAILABLE:
            try:
                process = psutil.Process()
                return process.memory_info().rss / 1024 / 1024
            except Exception:
                pass
        return 0.0
    
    def get_memory_breakdown(self) -> Dict[str, float]:
        """Get detailed memory breakdown if available"""
        if not PSUTIL_AVAILABLE:
            return {"total": 0.0}
            
        try:
            process = psutil.Process()
            memory_info = process.memory_info()
            
            return {
                "rss": memory_info.rss / 1024 / 1024,  # Resident Set Size
                "vms": memory_info.vms / 1024 / 1024,  # Virtual Memory Size
                "percent": process.memory_percent(),
                "available": psutil.virtual_memory().available / 1024 / 1024
            }
        except Exception:
            return {"total": 0.0}

def memory_profile(operation_name: str = None):
    """
    Decorator to automatically monitor memory usage of functions.
    
    Example:
        @memory_profile("image_processing")
        async def process_image(image_bytes):
            # Function automatically monitored
            return processed_image
    """
    def decorator(func: Callable) -> Callable:
        func_name = operation_name or f"{func.__module__}.{func.__name__}"
        
        if asyncio.iscoroutinefunction(func):
            @functools.wraps(func)
            async def async_wrapper(*args, **kwargs):
                with MemoryMonitor(func_name) as monitor:
                    try:
                        result = await func(*args, **kwargs)
                        monitor.checkpoint("function_complete")
                        return result
                    except Exception as e:
                        monitor.checkpoint(f"error_{type(e).__name__}")
                        raise
            return async_wrapper
        else:
            @functools.wraps(func)
            def sync_wrapper(*args, **kwargs):
                with MemoryMonitor(func_name) as monitor:
                    try:
                        result = func(*args, **kwargs)
                        monitor.checkpoint("function_complete")
                        return result
                    except Exception as e:
                        monitor.checkpoint(f"error_{type(e).__name__}")
                        raise
            return sync_wrapper
    return decorator

class MemoryOptimizedProcessor:
    """
    Base class for memory-optimized processing operations.
    Provides automatic cleanup and monitoring.
    """
    
    def __init__(self, operation_name: str):
        self.operation_name = operation_name
        self.monitor = MemoryMonitor(operation_name)
        self._cleanup_objects = []
        
    def __enter__(self):
        self.monitor.__enter__()
        return self
        
    def __exit__(self, exc_type, exc_val, exc_tb):
        # Clean up registered objects
        for obj in self._cleanup_objects:
            cleanup_memory(obj)
        self._cleanup_objects.clear()
        
        # Exit monitor
        self.monitor.__exit__(exc_type, exc_val, exc_tb)
    
    def register_for_cleanup(self, *objects):
        """Register objects for automatic cleanup"""
        self._cleanup_objects.extend(objects)
        return objects[-1] if objects else None
    
    def checkpoint(self, name: str):
        """Record a memory checkpoint"""
        return self.monitor.checkpoint(name)
    
    def immediate_cleanup(self, *objects):
        """Immediately clean up specific objects"""
        cleanup_memory(*objects)
        
        # Remove from cleanup list if present
        for obj in objects:
            if obj in self._cleanup_objects:
                self._cleanup_objects.remove(obj)

# Quick memory logging function
def log_memory_usage(operation: str) -> float:
    """Simple memory usage logger for quick checks"""
    if PSUTIL_AVAILABLE:
        try:
            process = psutil.Process()
            memory_mb = process.memory_info().rss / 1024 / 1024
            print(f"📊 Memory [{operation}]: {memory_mb:.1f} MB")
            return memory_mb
        except Exception:
            pass
    
    print(f"📊 Memory [{operation}]: monitoring unavailable")
    return 0.0

def get_system_memory_info() -> Dict[str, Any]:
    """Get overall system memory information"""
    if not PSUTIL_AVAILABLE:
        return {"available": False}
    
    try:
        vm = psutil.virtual_memory()
        return {
            "available": True,
            "total": vm.total / 1024 / 1024 / 1024,  # GB
            "available_mb": vm.available / 1024 / 1024,  # MB
            "percent_used": vm.percent,
            "free": vm.free / 1024 / 1024,  # MB
        }
    except Exception as e:
        return {"available": False, "error": str(e)}

# Memory leak detection
class MemoryLeakDetector:
    """
    Tracks memory usage over time to detect potential leaks.
    """
    
    def __init__(self, threshold_mb: float = 50.0):
        self.threshold_mb = threshold_mb
        self.baseline_memory = 0.0
        self.peak_memory = 0.0
        self.measurements = []
        
    def set_baseline(self):
        """Set the baseline memory usage"""
        self.baseline_memory = log_memory_usage("baseline")
        self.peak_memory = self.baseline_memory
        
    def check_for_leak(self, operation: str) -> bool:
        """Check if current memory usage indicates a leak"""
        current_memory = log_memory_usage(operation)
        self.peak_memory = max(self.peak_memory, current_memory)
        
        self.measurements.append({
            'operation': operation,
            'memory': current_memory,
            'time': time.time()
        })
        
        # Check for leak
        memory_increase = current_memory - self.baseline_memory
        
        if memory_increase > self.threshold_mb:
            print(f"🚨 MEMORY LEAK DETECTED in {operation}:")
            print(f"  • Baseline: {self.baseline_memory:.1f} MB")
            print(f"  • Current: {current_memory:.1f} MB")
            print(f"  • Increase: {memory_increase:.1f} MB")
            print(f"  • Peak: {self.peak_memory:.1f} MB")
            return True
            
        return False
    
    def get_summary(self) -> Dict[str, Any]:
        """Get memory usage summary"""
        if not self.measurements:
            return {"no_data": True}
            
        current_memory = self.measurements[-1]['memory']
        memory_increase = current_memory - self.baseline_memory
        
        return {
            "baseline_mb": self.baseline_memory,
            "current_mb": current_memory,
            "peak_mb": self.peak_memory,
            "increase_mb": memory_increase,
            "leak_detected": memory_increase > self.threshold_mb,
            "measurement_count": len(self.measurements)
        } 