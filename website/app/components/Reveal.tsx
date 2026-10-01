"use client";

import { useEffect } from "react";

/**
 * Adds `is-in` once to every `[data-reveal]` element as it scrolls into view,
 * and keeps `is-visible` on `[data-animate]` elements only while they are on
 * screen, so looping scenes never run, and never repaint, off screen.
 */
export default function Reveal() {
  useEffect(() => {
    const reveals = Array.from(document.querySelectorAll<HTMLElement>("[data-reveal]"));
    const animated = Array.from(document.querySelectorAll<HTMLElement>("[data-animate]"));
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (!("IntersectionObserver" in window) || reduce) {
      reveals.forEach((el) => el.classList.add("is-in"));
      animated.forEach((el) => el.classList.add("is-visible"));
      return;
    }
    const revealer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-in");
            revealer.unobserve(entry.target);
          }
        }
      },
      { rootMargin: "0px 0px -10% 0px", threshold: 0.1 },
    );
    const looper = new IntersectionObserver((entries) => {
      for (const entry of entries) entry.target.classList.toggle("is-visible", entry.isIntersecting);
    });
    reveals.forEach((el) => revealer.observe(el));
    animated.forEach((el) => looper.observe(el));
    return () => {
      revealer.disconnect();
      looper.disconnect();
    };
  }, []);
  return null;
}
