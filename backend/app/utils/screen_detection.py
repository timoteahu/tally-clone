"""
Screen Detection Utilities for Gym Photo Verification

This module implements OpenCV-based heuristics to detect if a photo
was taken of a screen (to prevent cheating in gym verification).

Detects:
- High rectangle-like edges (common with screens)
- Moiré patterns (pixel shimmer from photographing screens)
- Flat lighting (screens lack natural shadows/depth)
- Uniform brightness patterns
- Digital artifacts

Author: Joy Thief Team
"""

import cv2
import numpy as np
from typing import Tuple, Dict, Any
import io
from PIL import Image


class ScreenDetector:
    """
    Detects if an image was likely taken of a screen using multiple heuristics.
    """
    
    def __init__(self):
        # Thresholds for screen detection (tunable based on testing)
        self.EDGE_THRESHOLD = 0.15  # High edge density suggests screen borders
        self.MOIRE_THRESHOLD = 0.12  # Moiré pattern detection threshold
        self.BRIGHTNESS_UNIFORMITY_THRESHOLD = 0.85  # Flat lighting threshold
        self.RECTANGLE_THRESHOLD = 0.8  # Strong rectangular shape threshold
        self.DIGITAL_ARTIFACTS_THRESHOLD = 0.1  # Digital compression artifacts
        
        # Combined score threshold - if total score > this, likely a screen photo
        self.SCREEN_DETECTION_THRESHOLD = 0.6
    
    def analyze_image(self, image_bytes: bytes) -> Dict[str, Any]:
        """
        Analyze image to detect if it's a photo of a screen.
        
        Args:
            image_bytes: Raw image data
            
        Returns:
            Dictionary with analysis results and confidence score
        """
        try:
            # Convert bytes to OpenCV image
            img_array = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
            
            if img is None:
                return {"error": "Could not decode image", "is_screen": False, "confidence": 0}
            
            # Run all detection heuristics
            results = {
                "is_screen": False,
                "confidence": 0.0,
                "details": {},
                "reasoning": []
            }
            
            # 1. Edge Analysis - screens have sharp rectangular edges
            edge_score = self._analyze_edges(img)
            results["details"]["edge_score"] = edge_score
            
            # 2. Moiré Pattern Detection - interference patterns from screen pixels
            moire_score = self._detect_moire_patterns(img)
            results["details"]["moire_score"] = moire_score
            
            # 3. Brightness Uniformity - screens have flat, artificial lighting
            brightness_score = self._analyze_brightness_uniformity(img)
            results["details"]["brightness_uniformity"] = brightness_score
            
            # 4. Rectangle Detection - screen boundaries
            rectangle_score = self._detect_screen_rectangle(img)
            results["details"]["rectangle_score"] = rectangle_score
            
            # 5. Digital Artifacts - compression patterns typical of screen photos
            artifacts_score = self._detect_digital_artifacts(img)
            results["details"]["digital_artifacts"] = artifacts_score
            
            # Calculate combined confidence score
            confidence = self._calculate_confidence(
                edge_score, moire_score, brightness_score, 
                rectangle_score, artifacts_score
            )
            
            results["confidence"] = confidence
            results["is_screen"] = confidence > self.SCREEN_DETECTION_THRESHOLD
            
            # Generate human-readable reasoning
            results["reasoning"] = self._generate_reasoning(results["details"], confidence)
            
            return results
            
        except Exception as e:
            return {
                "error": f"Screen detection failed: {str(e)}", 
                "is_screen": False, 
                "confidence": 0
            }
    
    def _analyze_edges(self, img: np.ndarray) -> float:
        """
        Analyze edge density and patterns. Screens have sharp, rectangular edges.
        """
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        # Use Canny edge detection
        edges = cv2.Canny(gray, 50, 150, apertureSize=3)
        
        # Calculate edge density
        edge_pixels = np.sum(edges > 0)
        total_pixels = edges.shape[0] * edges.shape[1]
        edge_density = edge_pixels / total_pixels
        
        # Look for strong horizontal/vertical lines (screen borders)
        horizontal_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (25, 1))
        vertical_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (1, 25))
        
        horizontal_lines = cv2.morphologyEx(edges, cv2.MORPH_OPEN, horizontal_kernel)
        vertical_lines = cv2.morphologyEx(edges, cv2.MORPH_OPEN, vertical_kernel)
        
        h_score = np.sum(horizontal_lines > 0) / total_pixels
        v_score = np.sum(vertical_lines > 0) / total_pixels
        
        # Combine scores - high edge density + strong lines = likely screen
        line_score = (h_score + v_score) * 2
        combined_score = min(edge_density * 3 + line_score, 1.0)
        
        return combined_score
    
    def _detect_moire_patterns(self, img: np.ndarray) -> float:
        """
        Detect moiré patterns caused by camera sensor interference with screen pixels.
        """
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        # Apply FFT to detect periodic patterns
        f_transform = np.fft.fft2(gray)
        f_shift = np.fft.fftshift(f_transform)
        magnitude_spectrum = np.log(np.abs(f_shift) + 1)
        
        # Look for periodic patterns in frequency domain
        # Moiré patterns show up as regular frequency components
        h, w = magnitude_spectrum.shape
        center_h, center_w = h // 2, w // 2
        
        # Create a mask to exclude DC component and very low frequencies
        mask = np.zeros((h, w), dtype=np.uint8)
        cv2.circle(mask, (center_w, center_h), min(h, w) // 8, 255, -1)
        
        # Analyze frequency peaks outside the center
        masked_spectrum = magnitude_spectrum.copy()
        masked_spectrum[mask == 255] = 0
        
        # Calculate variance in frequency domain - moiré patterns create peaks
        freq_variance = np.var(masked_spectrum)
        
        # Also check for regular grid patterns using autocorrelation
        autocorr = cv2.matchTemplate(gray, gray[::4, ::4], cv2.TM_CCOEFF_NORMED)
        autocorr_peaks = np.sum(autocorr > 0.8)
        
        # Combine frequency analysis with autocorrelation
        moire_score = min((freq_variance / 1000) + (autocorr_peaks / 100), 1.0)
        
        return moire_score
    
    def _analyze_brightness_uniformity(self, img: np.ndarray) -> float:
        """
        Analyze lighting uniformity. Real-world scenes have shadows and depth,
        while screen photos have flat, artificial lighting.
        """
        # Convert to LAB color space for better brightness analysis
        lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
        l_channel = lab[:, :, 0]  # Lightness channel
        
        # Calculate brightness statistics
        mean_brightness = np.mean(l_channel)
        std_brightness = np.std(l_channel)
        
        # Calculate coefficient of variation (low = uniform lighting)
        cv_brightness = std_brightness / (mean_brightness + 1e-6)
        
        # Check for gradients - real photos have lighting gradients
        grad_x = cv2.Sobel(l_channel, cv2.CV_64F, 1, 0, ksize=3)
        grad_y = cv2.Sobel(l_channel, cv2.CV_64F, 0, 1, ksize=3)
        gradient_magnitude = np.sqrt(grad_x**2 + grad_y**2)
        avg_gradient = np.mean(gradient_magnitude)
        
        # Uniform brightness + low gradients = likely screen
        uniformity_score = 1.0 - cv_brightness  # Higher score for more uniform
        gradient_score = 1.0 - min(avg_gradient / 50, 1.0)  # Lower gradients = higher score
        
        combined_score = (uniformity_score + gradient_score) / 2
        
        return combined_score
    
    def _detect_screen_rectangle(self, img: np.ndarray) -> float:
        """
        Detect rectangular screen boundaries using contour analysis.
        """
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        # Edge detection
        edges = cv2.Canny(gray, 50, 150)
        
        # Find contours
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        h, w = img.shape[:2]
        total_area = h * w
        
        max_rectangle_score = 0
        
        for contour in contours:
            # Approximate contour to polygon
            epsilon = 0.02 * cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, epsilon, True)
            
            # Check if it's roughly rectangular (4 vertices)
            if len(approx) == 4:
                area = cv2.contourArea(contour)
                
                # Must be a significant portion of the image
                if area > total_area * 0.1:
                    # Check if it's actually rectangular
                    rect = cv2.minAreaRect(contour)
                    box = cv2.boxPoints(rect)
                    box_area = cv2.contourArea(box)
                    
                    # How close is the contour to a perfect rectangle?
                    rectangularity = area / (box_area + 1e-6)
                    
                    # How much of the image does it cover?
                    coverage = area / total_area
                    
                    rectangle_score = rectangularity * coverage
                    max_rectangle_score = max(max_rectangle_score, rectangle_score)
        
        return min(max_rectangle_score, 1.0)
    
    def _detect_digital_artifacts(self, img: np.ndarray) -> float:
        """
        Detect digital compression artifacts and pixelation typical of screen photos.
        """
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        # Look for blocking artifacts (JPEG compression from screens)
        # Use discrete cosine transform to find 8x8 block patterns
        h, w = gray.shape
        
        # Divide image into 8x8 blocks and analyze DCT coefficients
        block_variance = []
        for i in range(0, h - 8, 8):
            for j in range(0, w - 8, 8):
                block = gray[i:i+8, j:j+8].astype(np.float32)
                dct_block = cv2.dct(block)
                
                # High-frequency components indicate blocking artifacts
                high_freq = dct_block[4:, 4:]
                block_variance.append(np.var(high_freq))
        
        if block_variance:
            avg_block_variance = np.mean(block_variance)
            artifacts_score = min(avg_block_variance / 100, 1.0)
        else:
            artifacts_score = 0
        
        # Also check for regular pixel patterns (screen subpixels)
        # Look for repeating patterns in small scales
        small_gray = cv2.resize(gray, (gray.shape[1]//4, gray.shape[0]//4))
        pattern_score = 0
        
        for scale in [2, 3, 4]:
            kernel = np.ones((scale, scale), np.uint8)
            eroded = cv2.erode(small_gray, kernel, iterations=1)
            dilated = cv2.dilate(eroded, kernel, iterations=1)
            pattern_diff = np.mean(np.abs(small_gray.astype(float) - dilated.astype(float)))
            pattern_score += pattern_diff / 255.0
        
        pattern_score /= 3  # Average across scales
        
        combined_score = (artifacts_score + pattern_score) / 2
        return min(combined_score, 1.0)
    
    def _calculate_confidence(self, edge_score: float, moire_score: float, 
                            brightness_score: float, rectangle_score: float, 
                            artifacts_score: float) -> float:
        """
        Calculate overall confidence that image is a screen photo.
        Weights based on importance and reliability of each heuristic.
        """
        # Weighted combination of all scores
        weights = {
            'edges': 0.25,      # Strong rectangular edges are very indicative
            'moire': 0.20,      # Moiré patterns are highly specific to screens
            'brightness': 0.20, # Flat lighting is common in screen photos
            'rectangle': 0.25,  # Large rectangular shapes suggest screen boundaries
            'artifacts': 0.10   # Digital artifacts are supplementary evidence
        }
        
        weighted_score = (
            edge_score * weights['edges'] +
            moire_score * weights['moire'] +
            brightness_score * weights['brightness'] +
            rectangle_score * weights['rectangle'] +
            artifacts_score * weights['artifacts']
        )
        
        return min(weighted_score, 1.0)
    
    def _generate_reasoning(self, details: Dict[str, float], confidence: float) -> list:
        """
        Generate human-readable reasoning for the detection result.
        """
        reasoning = []
        
        if details.get("edge_score", 0) > self.EDGE_THRESHOLD:
            reasoning.append("High edge density with rectangular patterns detected")
        
        if details.get("moire_score", 0) > self.MOIRE_THRESHOLD:
            reasoning.append("Moiré interference patterns found (typical of screen photography)")
        
        if details.get("brightness_uniformity", 0) > self.BRIGHTNESS_UNIFORMITY_THRESHOLD:
            reasoning.append("Unnaturally uniform lighting detected")
        
        if details.get("rectangle_score", 0) > self.RECTANGLE_THRESHOLD:
            reasoning.append("Large rectangular boundary detected")
        
        if details.get("digital_artifacts", 0) > self.DIGITAL_ARTIFACTS_THRESHOLD:
            reasoning.append("Digital compression artifacts present")
        
        if confidence > self.SCREEN_DETECTION_THRESHOLD:
            reasoning.append(f"Combined confidence score: {confidence:.2f} (threshold: {self.SCREEN_DETECTION_THRESHOLD})")
        
        if not reasoning:
            reasoning.append("Image appears to be a genuine photograph")
        
        return reasoning


def detect_screen_photo(image_bytes: bytes) -> Dict[str, Any]:
    """
    Convenience function to detect if an image is a screen photo.
    
    Args:
        image_bytes: Raw image data
        
    Returns:
        Dictionary with detection results
    """
    detector = ScreenDetector()
    return detector.analyze_image(image_bytes)


def is_screen_photo(image_bytes: bytes, confidence_threshold: float = 0.6) -> bool:
    """
    Simple boolean check if image is likely a screen photo.
    
    Args:
        image_bytes: Raw image data
        confidence_threshold: Minimum confidence to consider as screen photo
        
    Returns:
        True if likely a screen photo, False otherwise
    """
    result = detect_screen_photo(image_bytes)
    return result.get("confidence", 0) > confidence_threshold 