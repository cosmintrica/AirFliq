import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://airfliq.vercel.app"),
  alternates: {
    canonical: "/",
  },
  title: "AirFliq | AirDrop in one move on Mac",
  description:
    "Right-click in Finder, drop on a magnetic target, press a shortcut or click the menu bar, and Apple's AirDrop opens. Built in public for RevenueCat Shipaton 2026.",
  icons: {
    icon: "/assets/airfliq-icon-256.png",
    shortcut: "/assets/airfliq-icon-256.png",
    apple: "/assets/airfliq-icon-256.png",
  },
  openGraph: {
    url: "/",
    title: "AirFliq | AirDrop in one move on Mac",
    description: "Right-click, drop, shortcut or menu bar: Apple's AirDrop in one move. No account, no servers.",
    type: "website",
    images: [
      {
        url: "/og-airfliq.png",
        width: 1200,
        height: 630,
        alt: "AirFliq: AirDrop in one move",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "AirFliq | AirDrop in one move on Mac",
    description: "Right-click, drop, shortcut or menu bar: Apple's AirDrop in one move. No account, no servers.",
    images: ["/og-airfliq.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className={`${geistSans.variable} ${geistMono.variable}`}>
        {children}
      </body>
    </html>
  );
}
