"use client";

import { useState } from "react";

/**
 * Shows the film's poster and loads YouTube's own player only when someone
 * presses play, so views count on YouTube and the page stays light.
 */
export default function FilmEmbed({ id, title }: { id: string; title: string }) {
  const [playing, setPlaying] = useState(false);
  return (
    <div className="film-frame">
      {playing ? (
        <iframe
          src={`https://www.youtube.com/embed/${id}?autoplay=1&rel=0&playsinline=1`}
          title={title}
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
          referrerPolicy="strict-origin-when-cross-origin"
          allowFullScreen
        />
      ) : (
        <button type="button" className="film-poster" onClick={() => setPlaying(true)} aria-label={`Play: ${title}`}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/film/poster.jpg" alt="" width={1280} height={720} loading="lazy" decoding="async" />
          <span className="film-play" aria-hidden="true">
            <svg viewBox="0 0 24 24" width="30" height="30">
              <path d="M8 5.5v13l11-6.5z" fill="currentColor" />
            </svg>
          </span>
          <span className="film-meta">
            <b>Watch the film</b>
            <small>62 seconds, rendered entirely from code</small>
          </span>
        </button>
      )}
    </div>
  );
}
