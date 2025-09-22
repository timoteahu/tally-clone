'use client';

import { useEffect, useRef } from 'react';

export default function NoiseTexture({ opacity = 0.03, className = "" }: { opacity?: number; className?: string }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Set canvas size
    canvas.width = 300;
    canvas.height = 300;

    // Create noise
    const imageData = ctx.createImageData(canvas.width, canvas.height);
    const data = imageData.data;

    for (let i = 0; i < data.length; i += 4) {
      const noise = Math.random() * 255;
      data[i] = noise;     // Red
      data[i + 1] = noise; // Green
      data[i + 2] = noise; // Blue
      data[i + 3] = 255;   // Alpha
    }

    ctx.putImageData(imageData, 0, 0);
  }, []);

  return (
    <div 
      className={`fixed inset-0 pointer-events-none mix-blend-overlay ${className}`}
      style={{ opacity }}
    >
      <canvas
        ref={canvasRef}
        className="w-full h-full"
        style={{
          filter: 'contrast(300%) brightness(100%)',
          backgroundRepeat: 'repeat',
          backgroundSize: '300px 300px',
          backgroundImage: `url(${canvasRef.current?.toDataURL()})`,
        }}
      />
    </div>
  );
}