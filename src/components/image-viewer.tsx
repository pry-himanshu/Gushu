import { useEffect, useCallback, useState } from "react";
import { X, ZoomIn, ZoomOut, RotateCcw } from "lucide-react";
import { cn } from "@/lib/utils";

interface ImageViewerProps {
  src: string;
  alt?: string;
  onClose: () => void;
}

export function ImageViewer({ src, alt, onClose }: ImageViewerProps) {
  const [scale, setScale] = useState(1);
  const [isDragging, setIsDragging] = useState(false);
  const [position, setPosition] = useState({ x: 0, y: 0 });
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 });

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
      if (e.key === "+" || e.key === "=") setScale((s) => Math.min(s + 0.25, 4));
      if (e.key === "-") setScale((s) => Math.max(s - 0.25, 0.5));
      if (e.key === "0") { setScale(1); setPosition({ x: 0, y: 0 }); }
    },
    [onClose],
  );

  useEffect(() => {
    document.addEventListener("keydown", handleKeyDown);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "";
    };
  }, [handleKeyDown]);

  const handleWheel = (e: React.WheelEvent) => {
    e.preventDefault();
    const delta = e.deltaY > 0 ? -0.1 : 0.1;
    setScale((s) => Math.max(0.5, Math.min(4, s + delta)));
  };

  const handleMouseDown = (e: React.MouseEvent) => {
    if (scale <= 1) return;
    setIsDragging(true);
    setDragStart({ x: e.clientX - position.x, y: e.clientY - position.y });
  };

  const handleMouseMove = (e: React.MouseEvent) => {
    if (!isDragging) return;
    setPosition({ x: e.clientX - dragStart.x, y: e.clientY - dragStart.y });
  };

  const handleMouseUp = () => setIsDragging(false);

  const reset = () => { setScale(1); setPosition({ x: 0, y: 0 }); };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/90 backdrop-blur-xl" />

      {/* Controls */}
      <div className="absolute top-4 left-1/2 z-10 flex -translate-x-1/2 items-center gap-1 rounded-2xl border border-white/10 bg-black/60 px-3 py-2 backdrop-blur-md shadow-2xl">
        <button
          onClick={() => setScale((s) => Math.max(0.5, s - 0.25))}
          className="flex size-8 items-center justify-center rounded-xl text-white/70 transition-colors hover:bg-white/10 hover:text-white"
          aria-label="Zoom out"
        >
          <ZoomOut className="size-4" />
        </button>
        <span className="min-w-[3rem] text-center text-xs tabular-nums text-white/60">
          {Math.round(scale * 100)}%
        </span>
        <button
          onClick={() => setScale((s) => Math.min(4, s + 0.25))}
          className="flex size-8 items-center justify-center rounded-xl text-white/70 transition-colors hover:bg-white/10 hover:text-white"
          aria-label="Zoom in"
        >
          <ZoomIn className="size-4" />
        </button>
        {scale !== 1 && (
          <button
            onClick={reset}
            className="flex size-8 items-center justify-center rounded-xl text-white/70 transition-colors hover:bg-white/10 hover:text-white"
            aria-label="Reset zoom"
          >
            <RotateCcw className="size-3.5" />
          </button>
        )}
      </div>

      {/* Close button */}
      <button
        onClick={onClose}
        className="absolute right-4 top-4 z-10 flex size-10 items-center justify-center rounded-full border border-white/10 bg-black/60 text-white/80 backdrop-blur-md shadow-lg transition-all hover:scale-110 hover:bg-white/10 hover:text-white"
        aria-label="Close"
      >
        <X className="size-5" />
      </button>

      {/* Image */}
      <div
        className={cn(
          "relative z-10 select-none",
          isDragging ? "cursor-grabbing" : scale > 1 ? "cursor-grab" : "cursor-default",
        )}
        onWheel={handleWheel}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
      >
        <img
          src={src}
          alt={alt ?? ""}
          draggable={false}
          className="max-h-[90vh] max-w-[90vw] rounded-2xl object-contain shadow-2xl transition-transform duration-150"
          style={{
            transform: `translate(${position.x}px, ${position.y}px) scale(${scale})`,
            transformOrigin: "center center",
          }}
        />
      </div>

      {/* Bottom hint */}
      <div className="absolute bottom-4 left-1/2 -translate-x-1/2 text-[10px] uppercase tracking-widest text-white/25 pointer-events-none">
        Scroll to zoom · Drag to pan · Esc to close
      </div>
    </div>
  );
}
